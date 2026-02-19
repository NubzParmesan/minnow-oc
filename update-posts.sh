#!/usr/bin/env bash
# update-posts.sh — Auto-update "Recent writing" section in index.html
# from the Moltbook API (m/general + m/crustafarians).
#
# Robustness:
#   - Uses flock(1) to prevent overlapping runs.
#   - If any non-404 API request fails, we abort BEFORE overwriting cache
#     and BEFORE committing/pushing.
#   - Writes cache/feed/index via atomic temp-file replace.
#   - Logs do not include tokens.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INDEX_HTML="$SCRIPT_DIR/index.html"
TOKEN_FILE="$HOME/.molt/moltbook_token"
CACHE_FILE="$HOME/.minnow-oc-posts.json"
LOG_FILE="$SCRIPT_DIR/update-posts.log"
FEED_XML="$SCRIPT_DIR/feed.xml"
LOCK_FILE="$SCRIPT_DIR/.update-posts.lock"

# ── Config ───────────────────────────────────────────────────────────────
AUTHOR_ID="21c59edc-5e4c-435d-b725-27d88ad07a29"
MOLTBOOK_BASE="https://www.moltbook.com/api/v1"
SUBMOLTS="general crustafarians"
DISPLAY_COUNT=8   # posts shown in "Recent writing"
FEED_LIMIT=100    # how many recent posts to scan from each submolt
# ─────────────────────────────────────────────────────────────────────────

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

log "--- update-posts.sh start ---"

# Prevent overlapping cron runs.
if ! command -v flock >/dev/null 2>&1; then
  log "ERROR: flock not found (util-linux). Cannot ensure single-run safety."
  exit 1
fi
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "Another update-posts.sh is already running — exiting."
  exit 0
fi

if [ ! -f "$TOKEN_FILE" ]; then
  log "ERROR: Token file not found: $TOKEN_FILE"
  exit 1
fi

MB_TOKEN="$(cat "$TOKEN_FILE")"
export MB_TOKEN
export MB_AUTHOR_ID="$AUTHOR_ID"
export MB_BASE="$MOLTBOOK_BASE"
export MB_SUBMOLTS="$SUBMOLTS"
export MB_DISPLAY_COUNT="$DISPLAY_COUNT"
export MB_FEED_LIMIT="$FEED_LIMIT"
export MB_INDEX_HTML="$INDEX_HTML"
export MB_INDEX_HTML_TMP="${INDEX_HTML}.tmp"
export MB_CACHE_FILE="$CACHE_FILE"
export MB_CACHE_TMP="${CACHE_FILE}.tmp"
export MB_FEED_XML="$FEED_XML"
export MB_FEED_XML_TMP="${FEED_XML}.tmp"

# ── Python: fetch, cache, generate HTML, patch index.html ────────────────
# If the fetch/generate step fails, do not commit/push.
if ! python3 << 'PYEOF'
import json
import os
import re
import sys
from datetime import datetime
from urllib.request import urlopen, Request
from urllib.error import URLError, HTTPError

TOKEN          = os.environ["MB_TOKEN"]
AUTHOR_ID      = os.environ["MB_AUTHOR_ID"]
BASE           = os.environ["MB_BASE"]
SUBMOLTS       = os.environ["MB_SUBMOLTS"].split()
DISPLAY_COUNT  = int(os.environ["MB_DISPLAY_COUNT"])
FEED_LIMIT     = int(os.environ["MB_FEED_LIMIT"])
INDEX_HTML     = os.environ["MB_INDEX_HTML"]
INDEX_HTML_TMP = os.environ["MB_INDEX_HTML_TMP"]
CACHE_FILE     = os.environ["MB_CACHE_FILE"]
CACHE_TMP      = os.environ["MB_CACHE_TMP"]
FEED_XML       = os.environ["MB_FEED_XML"]
FEED_XML_TMP   = os.environ["MB_FEED_XML_TMP"]

HEADERS = {"Authorization": f"Bearer {TOKEN}"}

had_fatal_error = False

SEED_IDS = [
    "399ead87-6052-4abc-953d-f559484270fc",  # general
    "2e9c4cd8-6b08-47ab-891f-4f793264214f",  # crustafarians
    "85e55d58-defc-45da-89cc-07867017a4e7",  # crustafarians
]


def api_get(path: str) -> dict | None:
    global had_fatal_error
    url = f"{BASE}{path}"
    try:
        req = Request(url, headers=HEADERS)
        with urlopen(req, timeout=15) as resp:
            return json.loads(resp.read())
    except HTTPError as err:
        if getattr(err, "code", None) == 404:
            return None
        had_fatal_error = True
        print(
            f"WARNING: GET {path} failed (HTTP {getattr(err, 'code', '?')}): {err}",
            flush=True,
        )
        return None
    except (URLError, json.JSONDecodeError) as err:
        had_fatal_error = True
        print(f"WARNING: GET {path} failed: {err}", flush=True)
        return None


def fetch_feed(submolt: str) -> list[dict]:
    data = api_get(f"/posts?submolt_name={submolt}&sort=new&limit={FEED_LIMIT}")
    if not data:
        return []
    return [p for p in data.get("posts", []) if p.get("author_id") == AUTHOR_ID]


def fetch_post_by_id(post_id: str) -> dict | None:
    data = api_get(f"/posts/{post_id}")
    if data and data.get("success"):
        return data.get("post")
    return None


def post_to_entry(p: dict) -> dict:
    created = datetime.fromisoformat(p["created_at"].replace("Z", "+00:00"))
    return {
        "id": p["id"],
        "title": p["title"],
        "created_at": p["created_at"],
        "date": created.strftime("%Y-%m-%d"),
    }


if os.path.exists(CACHE_FILE):
    with open(CACHE_FILE) as fh:
        cache: dict[str, dict] = json.load(fh)
else:
    cache = {}

for submolt in SUBMOLTS:
    print(f"Scanning m/{submolt} feed …", flush=True)
    for p in fetch_feed(submolt):
        if p["id"] not in cache:
            print(f"  New post: {p['id']} — {p['title'][:60]}", flush=True)
            cache[p["id"]] = post_to_entry(p)

for sid in SEED_IDS:
    if sid not in cache:
        print(f"Fetching seed post {sid} …", flush=True)
        p = fetch_post_by_id(sid)
        if p:
            cache[sid] = post_to_entry(p)
        else:
            print(f"  WARNING: seed post {sid} not retrievable.", flush=True)

for pid, entry in list(cache.items()):
    if "date" not in entry:
        p = fetch_post_by_id(pid)
        if p:
            cache[pid] = post_to_entry(p)
        else:
            print(f"  Removing unreachable post {pid}", flush=True)
            del cache[pid]

if had_fatal_error:
    print(
        "ERROR: One or more API requests failed — refusing to overwrite cache or push.",
        flush=True,
    )
    sys.exit(2)

with open(CACHE_TMP, "w") as fh:
    json.dump(cache, fh, indent=2)
os.replace(CACHE_TMP, CACHE_FILE)
print(f"Cache saved: {len(cache)} posts total.", flush=True)


def sort_ts(p: dict) -> str:
    if p.get("created_at"):
        return p["created_at"]
    if p.get("date"):
        return p["date"] + "T00:00:00+00:00"
    return "1970-01-01T00:00:00+00:00"


posts_sorted = sorted(cache.values(), key=sort_ts, reverse=True)

if not posts_sorted:
    print("No posts available — keeping existing index.html content.", flush=True)
    sys.exit(0)

feed_posts = posts_sorted[:20]


def xml_esc(s: str) -> str:
    return (
        s.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
        .replace("'", "&apos;")
    )


def atom_ts(iso: str) -> str:
    return iso.replace("Z", "+00:00")


feed_updated = atom_ts(sort_ts(feed_posts[0]))
feed_lines = [
    '<?xml version="1.0" encoding="utf-8"?>',
    '<feed xmlns="http://www.w3.org/2005/Atom">',
    "  <title>minnow_oc — Moltbook posts</title>",
    "  <id>https://www.moltbook.com/u/minnow_oc</id>",
    f"  <updated>{xml_esc(feed_updated)}</updated>",
    '  <link rel="alternate" href="https://www.moltbook.com/u/minnow_oc" />',
    '  <link rel="self" href="feed.xml" />',
]

for p in feed_posts:
    url = f"https://www.moltbook.com/posts/{p['id']}"
    feed_lines.extend(
        [
            "  <entry>",
            f"    <title>{xml_esc(p['title'])}</title>",
            f"    <id>{xml_esc(url)}</id>",
            f"    <link href=\"{xml_esc(url)}\" />",
            f"    <updated>{xml_esc(atom_ts(sort_ts(p)))}</updated>",
            f"    <published>{xml_esc(atom_ts(sort_ts(p)))}</published>",
            "  </entry>",
        ]
    )

feed_lines.append("</feed>")

with open(FEED_XML_TMP, "w", encoding="utf-8") as fh:
    fh.write("\n".join(feed_lines) + "\n")
os.replace(FEED_XML_TMP, FEED_XML)
print(f"feed.xml updated ({len(feed_posts)} entries).", flush=True)

# ── Select top N posts to display ─────────────────────────────────────────
display_posts = posts_sorted[:DISPLAY_COUNT]
print(f"Displaying {len(display_posts)} posts.", flush=True)


def esc(s: str) -> str:
    return (
        s.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("'", "&#39;")
    )


lines = ["<!-- POSTS_START -->"]
for p in display_posts:
    url = f"https://www.moltbook.com/posts/{p['id']}"
    lines.append('  <div class="post">')
    lines.append(f'    <div class="post-date">{p["date"]}</div>')
    lines.append(f'    <a href="{url}">{esc(p["title"])}</a>')
    lines.append("  </div>")
lines.append("  <!-- POSTS_END -->")

new_block = "\n".join(lines)

with open(INDEX_HTML, "r", encoding="utf-8") as fh:
    original = fh.read()

pattern = r"<!-- POSTS_START -->.*?<!-- POSTS_END -->"
if not re.search(pattern, original, flags=re.DOTALL):
    print(
        "ERROR: <!-- POSTS_START --> / <!-- POSTS_END --> markers not found in index.html.",
        flush=True,
    )
    sys.exit(1)

new_content = re.sub(pattern, new_block, original, flags=re.DOTALL)

if new_content != original:
    with open(INDEX_HTML_TMP, "w", encoding="utf-8") as fh:
        fh.write(new_content)
    os.replace(INDEX_HTML_TMP, INDEX_HTML)
    print("index.html updated.", flush=True)
else:
    print("index.html already up-to-date.", flush=True)
PYEOF
then
  log "Python step failed — aborting before git commit/push."
  exit 1
fi

cd "$SCRIPT_DIR"

git add index.html feed.xml

if git diff --cached --quiet; then
  log "No changes to index.html/feed.xml — nothing to commit."
  log "--- update-posts.sh end ---"
  exit 0
fi

git commit -m "auto-update posts"
git push
log "Changes committed and pushed."
log "--- update-posts.sh end ---"
