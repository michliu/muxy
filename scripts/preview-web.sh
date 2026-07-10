#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "Usage: scripts/preview-web.sh"
  echo "  Copies MuxyServer/Resources/web-terminal into the built app bundle so a"
  echo "  running dev app serves the latest frontend. Then hard-refresh the browser."
  exit 0
fi

SRC="$ROOT/MuxyServer/Resources/web-terminal"

DST=""
for d in "$ROOT"/.build/*/debug/Muxy_MuxyServer.bundle/web-terminal; do
  [[ -d "$d" ]] && DST="$d"
done

if [[ -z "$DST" ]]; then
  echo "No built app bundle found. Build/run the app first (scripts/dev.sh)." >&2
  exit 1
fi

echo "==> Syncing web-terminal into the bundle"
echo "    $SRC"
echo " -> $DST"
rsync -a --delete "$SRC/" "$DST/"
echo "==> Done. Hard-refresh the browser (Cmd+Shift+R)."
