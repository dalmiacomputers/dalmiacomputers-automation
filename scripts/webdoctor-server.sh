#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "Running server webdoctor at $ROOT"

if command -v php >/dev/null 2>&1; then
  if [ -f "$ROOT/tools/regenerate_sitemap.php" ]; then
    php "$ROOT/tools/regenerate_sitemap.php" || true
  fi
fi

if [ -d "$ROOT/cache" ]; then
  rm -rf "$ROOT/cache/*" || true
fi

if [ -f "$ROOT/final_chhama_run.ps1" ]; then
  if command -v pwsh >/dev/null 2>&1; then
    pwsh -NoProfile -NonInteractive -File "$ROOT/final_chhama_run.ps1" || true
  fi
fi

echo "Server-side WebDoctor completed."
