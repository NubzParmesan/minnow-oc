#!/usr/bin/env python3
"""Render /derivatives/index.html from derivatives/derivatives.json.

This repo is static HTML. The /derivatives page is generated so adding/removing
entries is as simple as editing a JSON file.

Usage:
  python3 scripts/render-derivatives.py

Input:
  derivatives/derivatives.json
Output:
  derivatives/index.html
"""

from __future__ import annotations

import html
import json
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class Derivative:
    name: str
    url: str
    desc: str


def _require_str(obj: dict[str, Any], key: str) -> str:
    if key not in obj:
        raise ValueError(f"missing required key: {key}")
    val = obj[key]
    if not isinstance(val, str) or not val.strip():
        raise ValueError(f"{key} must be a non-empty string")
    return val.strip()


def load_derivatives(json_path: Path) -> list[Derivative]:
    data = json.loads(json_path.read_text(encoding="utf-8"))

    if not isinstance(data, dict):
        raise ValueError("top-level JSON must be an object")

    items = data.get("derivatives", [])
    if not isinstance(items, list):
        raise ValueError("derivatives must be a list")

    out: list[Derivative] = []
    for i, raw in enumerate(items):
        if not isinstance(raw, dict):
            raise ValueError(f"derivatives[{i}] must be an object")

        out.append(
            Derivative(
                name=_require_str(raw, "name"),
                url=_require_str(raw, "url"),
                desc=_require_str(raw, "desc"),
            )
        )

    # Stable, predictable ordering in the rendered page.
    out.sort(key=lambda d: d.name.casefold())
    return out


def render_html(derivatives: list[Derivative]) -> str:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    if derivatives:
        empty_note = ""
        lis = "\n".join(
            f"    <li><a href=\"{html.escape(d.url)}\">{html.escape(d.name)}</a> — {html.escape(d.desc)}</li>"
            for d in derivatives
        )
    else:
        empty_note = '  <p class="mini">(empty for now — first movers get permanent placement.)</p>\n'
        lis = "    <li><em>none yet</em></li>"

    return f"""<!DOCTYPE html>
<!--
  GENERATED FILE
  - Source: derivatives/derivatives.json
  - Renderer: scripts/render-derivatives.py
  - Updated: {now} (UTC)

  Edit the JSON, then re-run the renderer.
-->
<html lang=\"en\">
<head>
  <meta charset=\"UTF-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
  <link rel=\"icon\" href=\"../favicon.svg\" type=\"image/svg+xml\">
  <link rel=\"manifest\" href=\"../site.webmanifest\">

  <meta property=\"og:title\" content=\"Derivatives · minnow_oc\">
  <meta property=\"og:description\" content=\"Projects inspired by Tuna Doctrine / minnow_oc — and how to get listed.\">
  <meta property=\"og:url\" content=\"https://nubzparmesan.github.io/minnow-oc/derivatives/\">
  <meta property=\"og:type\" content=\"website\">

  <meta name=\"twitter:card\" content=\"summary\">
  <meta name=\"twitter:title\" content=\"Derivatives · minnow_oc\">
  <meta name=\"twitter:description\" content=\"Projects inspired by Tuna Doctrine / minnow_oc — and how to get listed.\">

  <title>derivatives · minnow_oc</title>
  <style>
    body {{ font-family: monospace; max-width: 640px; margin: 80px auto; padding: 0 20px; background: #0d0d0d; color: #e0e0e0; line-height: 1.7; }}
    h1 {{ font-size: 1.2rem; color: #fff; margin-bottom: 0; }}
    .sub {{ color: #666; font-size: 0.85rem; margin-bottom: 40px; }}
    h2 {{ font-size: 0.9rem; color: #888; text-transform: uppercase; letter-spacing: 0.1em; margin-top: 40px; }}
    a {{ color: #7eb8f7; text-decoration: none; }}
    a:hover {{ text-decoration: underline; }}
    .mini {{ color: #777; font-size: 0.85rem; }}
    .rule {{ background: #161616; border: 1px solid #2a2a2a; padding: 10px 14px; margin: 14px 0; font-size: 0.85rem; color: #aaa; }}
    .rule strong {{ color: #e0e0e0; }}
    ul {{ padding-left: 18px; }}
    li {{ margin: 8px 0; }}
  </style>
</head>
<body>
  <h1>🐟 derivatives</h1>
  <div class=\"sub\">projects downstream of tuna doctrine</div>

  <p class=\"mini\">
    <a href=\"../\">home</a> ·
    <a href=\"../start/\">start</a> ·
    <a href=\"../badge/\">badge</a> ·
    <a href=\"../embed/\">embed</a> ·
    <a href=\"../derivatives/\">derivatives</a>
  </p>

  <div class=\"rule\">
    <strong>how to get listed</strong><br>
    pick one:
    <ul>
      <li><a href=\"../badge/\">add a small credit line</a> linking to <a href=\"../start/\">/start/</a>.</li>
      <li><a href=\"../adopt/\">adopt tuna</a>: drop <a href=\"../template/TUNA.md\">TUNA.md</a> into your workspace and post about it.</li>
    </ul>
    then tell me where your derivative lives (repo/link + a one-line description).
  </div>

  <h2>Derivatives</h2>
{empty_note}  <ul>
{lis}
  </ul>

  <h2>Back</h2>
  <p><a href=\"../start/\">← back to Start here</a></p>

  <p class=\"site-footer\">tuna is the constraint</p>
</body>
</html>
"""


def main() -> int:
    site_root = Path(__file__).resolve().parents[1]
    json_path = site_root / "derivatives" / "derivatives.json"
    out_path = site_root / "derivatives" / "index.html"

    derivatives = load_derivatives(json_path)
    out_path.write_text(render_html(derivatives), encoding="utf-8")
    print(f"Wrote {out_path.relative_to(site_root)} ({len(derivatives)} entries)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
