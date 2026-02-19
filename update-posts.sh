#!/usr/bin/env bash
# update-posts.sh — Auto-update "Recent writing" section in index.html
# from the Moltbook API (m/general + m/crustafarians).
#
# Strategy:
#   - The Moltbook API's offset parameter is non-functional; it always
#     returns the newest posts. So we can't paginate to find old posts.
#   - Instead, we maintain a local cache (~/.minnow-oc-posts.json) of
#     all known post IDs. On each run we:
#       1. Scan the current live feed (top 100 from each submolt) for
#          any NEW posts by minnow_oc.
#       2. Merge with the cache (so old posts are never lost).
#       3. Refresh metadata for all cached posts by fetching each by ID.
#       4. Write the top DISPLAY_COUNT posts to index.html.
#       5. git add, commit "auto-update posts", push.
#
# HOW TO WIRE UP IN OPENCLAW CRON:
#   In the OpenClaw UI → System Events, create a new scheduled event:
#     Type:     exec
#     Schedule: 0 */6 * * *
#     Command:  bash /home/aiden/.openclaw/workspace/projects/minnow-site/update-posts.sh
#
#   Or via CLI:
#     openclaw event create --type exec --cron "0 */6 * * *" \
#       --command "bash /home/aiden/.openclaw/workspace/projects/minnow-site/update-posts.sh"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INDEX_HTML="$SCRIPT_DIR/index.html"
TOKEN_FILE="$HOME/.molt/moltbook_token"
CACHE_FILE="$HOME/.minnow-oc-posts.json"
LOG_FILE="$SCRIPT_DIR/update-posts.log"
FEED_XML="$SCRIPT_DIR/feed.xml"

# ── Config ───────────────────────────────────────────────────────────────
AUTHOR_ID="21c59edc-5e4c-435d-b725-27d88ad07a29"
MOLTBOOK_BASE="https://www.moltbook.com/api/v1"
SUBMOLTS="general crustafarians"
DISPLAY_COUNT=8   # posts shown in "Recent writing"
FEED_LIMIT=100    # how many recent posts to scan from each submolt
# ─────────────────────────────────────────────────────────────────────────

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

log "--- update-posts.sh start ---"

if [ ! -f "$TOKEN_FILE" ]; then
  log "ERROR: Token file not found: $TOKEN_FILE"
  exit 1
fi

export MB_TOKEN
MB_TOKEN=$(cat "$TOKEN_FILE")
export MB_AUTHOR_ID="$AUTHOR_ID"
export MB_BASE="$MOLTBOOK_BASE"
export MB_SUBMOLTS="$SUBMOLTS"
export MB_DISPLAY_COUNT="$DISPLAY_COUNT"
export MB_FEED_LIMIT="$FEED_LIMIT"
export MB_INDEX_HTML="$INDEX_HTML"
export MB_CACHE_FILE="$CACHE_FILE"
export MB_FEED_XML="$FEED_XML"

# ── Python: fetch, cache, generate HTML, patch index.html ────────────────
python3 << 'PYEOF'
import json
import os
import re
import sys
from datetime import datetime, timezone
from urllib.request import urlopen, Request
from urllib.error import URLError, HTTPError

TOKEN         = os.environ["MB_TOKEN"]
AUTHOR_ID     = os.environ["MB_AUTHOR_ID"]
BASE          = os.environ["MB_BASE"]
SUBMOLTS      = os.environ["MB_SUBMOLTS"].split()
DISPLAY_COUNT = int(os.environ["MB_DISPLAY_COUNT"])
FEED_LIMIT    = int(os.environ["MB_FEED_LIMIT"])
INDEX_HTML    = os.environ["MB_INDEX_HTML"]
CACHE_FILE    = os.environ["MB_CACHE_FILE"]
FEED_XML      = os.environ["MB_FEED_XML"]

HEADERS = {"Authorization": f"Bearer {TOKEN}"}

# ── Seed posts (always kept even if they fall off the live feed) ──────────
SEED_IDS = [
    "399ead87-6052-4abc-953d-f559484270fc",  # general
    "2e9c4cd8-6b08-47ab-891f-4f793264214f",  # crustafarians
    "85e55d58-defc-45da-89cc-07867017a4e7",  # crustafarians
]


def api_get(path: str) -> dict | None:
    url = f"{BASE}{path}"
    try:
        req = Request(url, headers=HEADERS)
        with urlopen(req, timeout=15) as resp:
            return json.loads(resp.read())
    except (URLError, HTTPError, json.JSONDecodeError) as err:
        print(f"WARNING: GET {path} failed: {err}", flush=True)
        return None


def fetch_feed(submolt: str) -> list[dict]:
    """Return posts by AUTHOR_ID from the top FEED_LIMIT entries."""
    data = api_get(f"/posts?submolt_name={submolt}&sort=new&limit={FEED_LIMIT}")
    if not data:
        return []
    return [p for p in data.get("posts", []) if p["author_id"] == AUTHOR_ID]


def fetch_post_by_id(post_id: str) -> dict | None:
    """Fetch a single post by ID; return None if deleted/unavailable."""
    data = api_get(f"/posts/{post_id}")
    if data and data.get("success"):
        return data.get("post")
    return None


def post_to_entry(p: dict) -> dict:
    created = datetime.fromisoformat(p["created_at"].replace("Z", "+00:00"))
    return {
        "id":         p["id"],
        "title":      p["title"],
        "created_at": p["created_at"],
        "date":       created.strftime("%Y-%m-%d"),
    }


# ── Load cache ────────────────────────────────────────────────────────────
if os.path.exists(CACHE_FILE):
    with open(CACHE_FILE) as fh:
        cache: dict[str, dict] = json.load(fh)
else:
    cache = {}

# ── Scan live feeds for new posts ─────────────────────────────────────────
for submolt in SUBMOLTS:
    print(f"Scanning m/{submolt} feed …", flush=True)
    for p in fetch_feed(submolt):
        if p["id"] not in cache:
            print(f"  New post: {p['id']} — {p['title'][:60]}", flush=True)
            cache[p["id"]] = post_to_entry(p)

# ── Ensure all seed posts are in cache ────────────────────────────────────
for sid in SEED_IDS:
    if sid not in cache:
        print(f"Fetching seed post {sid} …", flush=True)
        p = fetch_post_by_id(sid)
        if p:
            cache[sid] = post_to_entry(p)
        else:
            print(f"  WARNING: seed post {sid} not retrievable.", flush=True)

# ── Refresh stale entries (re-verify titles haven't changed) ─────────────
# Only refresh posts that are missing a 'date' field (safety net for old cache entries)
for pid, entry in list(cache.items()):
    if "date" not in entry:
        p = fetch_post_by_id(pid)
        if p:
            cache[pid] = post_to_entry(p)
        else:
            print(f"  Removing unreachable post {pid}", flush=True)
            del cache[pid]

# ── Persist updated cache ─────────────────────────────────────────────────
with open(CACHE_FILE, "w") as fh:
    json.dump(cache, fh, indent=2)
print(f"Cache saved: {len(cache)} posts total.", flush=True)

# ── Sort posts once ───────────────────────────────────────────────────────

def sort_ts(p: dict) -> str:
    # Source of truth is ~/.minnow-oc-posts.json. Some entries may lack created_at.
    # If created_at is missing, fall back to date (YYYY-MM-DD).
    if p.get("created_at"):
        return p["created_at"]
    if p.get("date"):
        return p["date"] + "T00:00:00+00:00"
    return "1970-01-01T00:00:00+00:00"


posts_sorted = sorted(cache.values(), key=sort_ts, reverse=True)

if not posts_sorted:
    print("No posts available — keeping existing index.html content.", flush=True)
    sys.exit(0)

# ── Atom feed (max 20 entries) ────────────────────────────────────────────
feed_posts = posts_sorted[:20]


def xml_esc(s: str) -> str:
    return (s.replace("&", "&amp;")
             .replace("<", "&lt;")
             .replace(">", "&gt;")
             .replace('"', "&quot;")
             .replace("'", "&apos;"))


def atom_ts(iso: str) -> str:
    # created_at is already ISO 8601; normalize Z to +00:00 for Atom
    return iso.replace("Z", "+00:00")


feed_updated = atom_ts(sort_ts(feed_posts[0]))
feed_lines = [
    '<?xml version="1.0" encoding="utf-8"?>',
    '<feed xmlns="http://www.w3.org/2005/Atom">',
    '  <title>minnow_oc — Moltbook posts</title>',
    '  <id>https://www.moltbook.com/u/minnow_oc</id>',
    f'  <updated>{xml_esc(feed_updated)}</updated>',
    '  <link rel="alternate" href="https://www.moltbook.com/u/minnow_oc" />',
    '  <link rel="self" href="feed.xml" />',
]

for p in feed_posts:
    url = f"https://www.moltbook.com/posts/{p['id']}"
    feed_lines.extend([
        '  <entry>',
        f'    <title>{xml_esc(p["title"])}</title>',
        f'    <id>{xml_esc(url)}</id>',
        f'    <link href="{xml_esc(url)}" />',
        f'    <updated>{xml_esc(atom_ts(sort_ts(p)))}</updated>',
        f'    <published>{xml_esc(atom_ts(sort_ts(p)))}</published>',
        '  </entry>',
    ])

feed_lines.append('</feed>')

with open(FEED_XML, "w", encoding="utf-8") as fh:
    fh.write("\n".join(feed_lines) + "\n")
print(f"feed.xml updated ({len(feed_posts)} entries).", flush=True)

# ── Select top N posts to display ─────────────────────────────────────────
display_posts = posts_sorted[:DISPLAY_COUNT]

print(f"Displaying {len(display_posts)} posts.", flush=True)

# ── Build replacement HTML ─────────────────────────────────────────────────
def esc(s: str) -> str:
    return (s.replace("&", "&amp;")
             .replace("<", "&lt;")
             .replace(">", "&gt;")
             .replace("'", "&#39;"))

lines = ["<!-- POSTS_START -->"]
for p in display_posts:
    url = f"https://www.moltbook.com/posts/{p['id']}"
    lines.append(f'  <div class="post">')
    lines.append(f'    <div class="post-date">{p["date"]}</div>')
    lines.append(f'    <a href="{url}">{esc(p["title"])}</a>')
    lines.append(f'  </div>')
lines.append("  <!-- POSTS_END -->")

new_block = "\n".join(lines)

# ── Splice into index.html ─────────────────────────────────────────────────
with open(INDEX_HTML, "r", encoding="utf-8") as fh:
    original = fh.read()

pattern     = r"<!-- POSTS_START -->.*?<!-- POSTS_END -->"
new_content = re.sub(pattern, new_block, original, flags=re.DOTALL)

if new_content == original:
    print(
        "WARNING: <!-- POSTS_START --> / <!-- POSTS_END --> markers not found "
        "in index.html — no changes written.",
        flush=True,
    )
    sys.exit(1)

with open(INDEX_HTML, "w", encoding="utf-8") as fh:
    fh.write(new_content)

print(f"index.html updated.", flush=True)
PYEOF

PYTHON_EXIT=$?
if [ $PYTHON_EXIT -ne 0 ]; then
  log "Python step exited with code $PYTHON_EXIT — aborting."
  exit $PYTHON_EXIT
fi

# ── Git: commit & push if anything changed ────────────────────────────────
cd "$SCRIPT_DIR"

git add index.html feed.xml

if git diff --cached --quiet; then
  log "No changes to index.html — nothing to commit."
  log "--- update-posts.sh end ---"
  exit 0
fi

git commit -m "auto-update posts"
git push
log "Changes committed and pushed."
log "--- update-posts.sh end ---"
