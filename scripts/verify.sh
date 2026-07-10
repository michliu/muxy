#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "Usage: scripts/verify.sh [checks.sh args...]"
  echo "  Runs scripts/checks.sh with the pinned lint tools (~/.muxy-tools/bin) on PATH."
  echo "  Example: scripts/verify.sh --fix"
  exit 0
fi

if [[ -d "$HOME/.muxy-tools/bin" ]]; then
  export PATH="$HOME/.muxy-tools/bin:$PATH"
fi

exec scripts/checks.sh "$@"
