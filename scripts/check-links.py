#!/usr/bin/env python3
"""Lightweight internal link checker for minnow-site.

Scans this repo for href="..." in HTML files and reports broken internal links.

Ignored hrefs:
- External links: http(s)://, //...
- Fragments: #...
- Schemes: mailto:, tel:, javascript:, data:

Special case:
- When deployed on GitHub Pages as a project site, URLs may be prefixed with
  /minnow-oc/ (or similar). For local checks, known base prefixes are stripped
  if the corresponding directory does not exist.

Exit codes:
  0 - no broken links found
  1 - broken links found
  2 - configuration/usage error
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlsplit


HREF_RE = re.compile(r"href\s*=\s*([\"'])(.*?)\1", re.IGNORECASE | re.DOTALL)


@dataclass(frozen=True)
class BrokenLink:
    source: Path
    href: str
    resolved: Path


def is_ignored_href(href: str) -> bool:
    h = href.strip()
    if not h:
        return True
    if h.startswith("#"):
        return True
    lowered = h.lower()
    return (
        lowered.startswith("http://")
        or lowered.startswith("https://")
        or lowered.startswith("mailto:")
        or lowered.startswith("tel:")
        or lowered.startswith("javascript:")
        or lowered.startswith("data:")
        or lowered.startswith("//")
    )


def candidate_targets(
    site_root: Path,
    source_file: Path,
    href: str,
    *,
    base_prefixes: tuple[str, ...] = ("/minnow-oc",),
) -> list[Path]:
    parts = urlsplit(href)
    path = parts.path

    if path.startswith("/"):
        for prefix in base_prefixes:
            if path == prefix or path.startswith(prefix + "/"):
                maybe_dir = site_root / prefix.lstrip("/")
                if not maybe_dir.exists():
                    path = path[len(prefix) :] or "/"
                break
        target = (site_root / path.lstrip("/")).resolve()
    else:
        target = (source_file.parent / path).resolve()

    try:
        target.relative_to(site_root.resolve())
    except ValueError:
        return [target]

    candidates: list[Path] = [target]

    if path.endswith("/") or target.suffix == "":
        candidates.append(target / "index.html")

    if target.suffix == "":
        candidates.append(target.with_suffix(".html"))

    seen: set[Path] = set()
    out: list[Path] = []
    for c in candidates:
        if c not in seen:
            seen.add(c)
            out.append(c)
    return out


def check_site(site_root: Path) -> list[BrokenLink]:
    broken: list[BrokenLink] = []

    html_files = sorted(site_root.rglob("*.html"))
    for f in html_files:
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except Exception as e:
            print(f"WARN: failed to read {f}: {e}", file=sys.stderr)
            continue

        for _quote, href in HREF_RE.findall(text):
            href = href.strip()
            if is_ignored_href(href):
                continue

            candidates = candidate_targets(site_root, f, href)
            if not any(c.exists() for c in candidates):
                broken.append(BrokenLink(source=f, href=href, resolved=candidates[0]))

    return broken


def main() -> int:
    site_root = Path(__file__).resolve().parents[1]

    broken = check_site(site_root)

    if broken:
        print(f"Broken internal links: {len(broken)}")
        for b in broken:
            rel_source = b.source.relative_to(site_root)
            try:
                rel_resolved = b.resolved.relative_to(site_root)
            except ValueError:
                rel_resolved = b.resolved
            print(f"- {rel_source}: href=\"{b.href}\" → {rel_resolved}")
        return 1

    print("OK: no broken internal links found")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
