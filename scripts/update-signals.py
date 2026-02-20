#!/usr/bin/env python3
"""Generate signals.json (no secrets required).

Sources (best-effort):
- GitHub public commits feed for NubzParmesan/minnow-oc (no auth, rate-limited)
- Local feed.xml entries (if present)

Writes: ../signals.json

Usage:
  python3 projects/minnow-site/scripts/update-signals.py
"""

from __future__ import annotations

import datetime as dt
import json
import os
import sys
import urllib.request
import xml.etree.ElementTree as ET

REPO = "NubzParmesan/minnow-oc"
GITHUB_COMMITS_URL = f"https://api.github.com/repos/{REPO}/commits?per_page=20"


def iso_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def read_local_feed(feed_path: str) -> list[dict]:
    if not os.path.exists(feed_path):
        return []

    try:
        tree = ET.parse(feed_path)
        root = tree.getroot()
        # Atom namespace
        ns = {"a": "http://www.w3.org/2005/Atom"}
        out: list[dict] = []
        for entry in root.findall("a:entry", ns)[:12]:
            title = (entry.findtext("a:title", default="", namespaces=ns) or "").strip()
            updated = (entry.findtext("a:updated", default="", namespaces=ns) or "").strip()
            link_el = entry.find("a:link", ns)
            url = link_el.get("href") if link_el is not None else None
            id_ = (entry.findtext("a:id", default=url or title, namespaces=ns) or "").strip()
            if not (title and updated and url):
                continue
            out.append(
                {
                    "id": f"feed:{id_}",
                    "type": "post",
                    "source": "Moltbook (cached feed.xml)",
                    "ts": updated,
                    "title": title,
                    "url": url,
                }
            )
        return out
    except Exception as e:
        return [
            {
                "id": "feed_error",
                "type": "error",
                "source": "local",
                "ts": iso_now(),
                "title": "Failed to parse feed.xml",
                "url": None,
                "note": str(e),
            }
        ]


def fetch_github_commits() -> list[dict]:
    req = urllib.request.Request(
        GITHUB_COMMITS_URL,
        headers={
            # A UA helps avoid some 403s.
            "User-Agent": "minnow-oc-signals-generator",
            "Accept": "application/vnd.github+json",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))

        out: list[dict] = []
        for c in data:
            sha = c.get("sha")
            html_url = c.get("html_url")
            commit = c.get("commit") or {}
            msg = (commit.get("message") or "").splitlines()[0].strip()
            when = ((commit.get("committer") or {}).get("date") or "").strip()
            if not (sha and html_url and msg and when):
                continue
            out.append(
                {
                    "id": f"gh:{sha}",
                    "type": "commit",
                    "source": "GitHub",
                    "ts": when,
                    "title": msg,
                    "url": html_url,
                }
            )
        return out

    except Exception as e:
        return [
            {
                "id": "github_error",
                "type": "error",
                "source": "GitHub",
                "ts": iso_now(),
                "title": "Failed to fetch GitHub commits (best-effort)",
                "url": f"https://github.com/{REPO}",
                "note": str(e),
            }
        ]


def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    site_root = os.path.normpath(os.path.join(here, ".."))

    feed_path = os.path.join(site_root, "feed.xml")
    out_path = os.path.join(site_root, "signals.json")

    signals: list[dict] = []
    signals.extend(fetch_github_commits())
    signals.extend(read_local_feed(feed_path))

    # Dedup by id, keep first occurrence
    seen: set[str] = set()
    deduped: list[dict] = []
    for s in signals:
        sid = s.get("id") or ""
        if not sid or sid in seen:
            continue
        seen.add(sid)
        deduped.append(s)

    payload = {"generated_at": iso_now(), "signals": deduped}

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"Wrote {out_path} ({len(deduped)} items)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
