#!/usr/bin/env python3
"""Build the downloadable starter kit zip.

This repo serves a static zip at:
  assets/crustafarian-starter-kit.zip

This script rebuilds that artifact from the current `template/` directory.

Design goals:
- Include *everything* in template/ (including new files like TUNA.md)
- Produce stable, deterministic-ish output (sorted paths, fixed timestamps)
"""

from __future__ import annotations

import os
import sys
import zipfile
from pathlib import Path


FIXED_ZIP_DT = (1980, 1, 1, 0, 0, 0)


def iter_template_files(template_dir: Path) -> list[Path]:
    files: list[Path] = []
    for p in template_dir.rglob("*"):
        if p.is_dir():
            continue
        rel = p.relative_to(template_dir)
        # Ignore common junk
        parts = set(rel.parts)
        if ".DS_Store" in parts or "__pycache__" in parts:
            continue
        files.append(p)
    return sorted(files, key=lambda x: str(x).lower())


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    template_dir = repo_root / "template"
    out_zip = repo_root / "assets" / "crustafarian-starter-kit.zip"

    if not template_dir.exists():
        print(f"ERROR: missing template dir: {template_dir}", file=sys.stderr)
        return 2

    files = iter_template_files(template_dir)
    if not files:
        print("ERROR: template is empty; refusing to write zip", file=sys.stderr)
        return 2

    out_zip.parent.mkdir(parents=True, exist_ok=True)

    tmp_zip = out_zip.with_suffix(out_zip.suffix + ".tmp")
    if tmp_zip.exists():
        tmp_zip.unlink()

    # Write
    with zipfile.ZipFile(tmp_zip, "w", compression=zipfile.ZIP_DEFLATED) as z:
        for f in files:
            rel = f.relative_to(repo_root)
            arcname = str(rel).replace(os.sep, "/")

            info = zipfile.ZipInfo(arcname)
            info.date_time = FIXED_ZIP_DT

            # Preserve basic file mode (read/write bits) when possible
            st = f.stat()
            # external_attr: top 16 bits are unix perms
            info.external_attr = (st.st_mode & 0xFFFF) << 16

            data = f.read_bytes()
            z.writestr(info, data)

    tmp_zip.replace(out_zip)

    print(f"Wrote: {out_zip}")
    print(f"Files: {len(files)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
