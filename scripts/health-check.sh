#!/usr/bin/env bash
set -euo pipefail

# Run from repo root regardless of where invoked
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

run() {
  echo "+ $*" >&2
  "$@"
}

# 1) Link checks
run python3 scripts/check-links.py

# 2) Optional signals updater
if [[ -f scripts/update-signals.py ]]; then
  run python3 scripts/update-signals.py
else
  echo "(skip) scripts/update-signals.py not found" >&2
fi

# 3) Moltbook URL sanity: ensure post links use /post/ (not /posts/ or /p/)
#    User pages like /u/<handle> are fine.
if grep -RIn --exclude-dir=.git -E "https?://(www\\.)?moltbook\\.com/(posts|p)/" .; then
  echo "ERROR: Found Moltbook URLs not using /post/. Please switch to https://www.moltbook.com/post/<id>." >&2
  exit 1
fi

echo "OK: health check passed" >&2
