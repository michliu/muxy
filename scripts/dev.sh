#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"
export PATH="/usr/bin:$PATH"

NO_BUILD=false
for arg in "$@"; do
  case "$arg" in
    --no-build) NO_BUILD=true ;;
    -h | --help)
      echo "Usage: scripts/dev.sh [--no-build]"
      echo "  Builds the debug app and launches it directly (avoids run-dev.sh's swift PATH issue)."
      echo "  --no-build   Skip the build and just launch the existing binary"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

BINARY="$ROOT/.build/debug/Muxy"

if [[ "$NO_BUILD" == false ]]; then
  echo "==> Building Muxy (debug)"
  swift build --product Muxy
fi

if [[ ! -x "$BINARY" ]]; then
  echo "Binary not found at $BINARY. Run 'scripts/dev.sh' without --no-build first." >&2
  exit 1
fi

echo "==> Launching $BINARY"
exec "$BINARY"
