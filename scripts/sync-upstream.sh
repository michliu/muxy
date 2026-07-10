#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

USE_MERGE=false
RUN_CHECKS=false
for arg in "$@"; do
  case "$arg" in
    --merge) USE_MERGE=true ;;
    --check) RUN_CHECKS=true ;;
    -h | --help)
      echo "Usage: scripts/sync-upstream.sh [--merge] [--check]"
      echo "  --merge   Merge main into the current branch instead of rebasing"
      echo "  --check   Run scripts/checks.sh --fix after a successful sync"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

BRANCH="$(git rev-parse --abbrev-ref HEAD)"

if [[ "$BRANCH" == "main" || "$BRANCH" == "HEAD" ]]; then
  echo "Switch to your feature branch first (currently on '$BRANCH')." >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree has uncommitted changes. Commit or stash them first." >&2
  exit 1
fi

echo "==> Fetching origin"
git fetch origin

echo "==> Fast-forwarding main to origin/main"
git checkout main
if ! git merge --ff-only origin/main; then
  echo "Local main diverged from origin/main; resolve it manually." >&2
  git checkout "$BRANCH"
  exit 1
fi
git checkout "$BRANCH"

CONFLICT_HINT="Likely files: Package.swift, MobileServerService.swift, MobileSettingsView.swift"

if [[ "$USE_MERGE" == true ]]; then
  echo "==> Merging main into $BRANCH"
  if ! git merge main; then
    echo ""
    echo "Merge conflicts. Resolve them, then: git add <files> && git commit"
    echo "$CONFLICT_HINT"
    exit 1
  fi
else
  echo "==> Rebasing $BRANCH onto main"
  if ! git rebase main; then
    echo ""
    echo "Rebase conflicts. Resolve them, then: git add <files> && git rebase --continue"
    echo "  (or abort with: git rebase --abort)"
    echo "$CONFLICT_HINT"
    exit 1
  fi
fi

echo "==> '$BRANCH' is now up to date with main"

if [[ "$RUN_CHECKS" == true ]]; then
  echo "==> Running checks"
  if [[ -d "$HOME/.muxy-tools/bin" ]]; then
    PATH="$HOME/.muxy-tools/bin:$PATH" scripts/checks.sh --fix
  else
    scripts/checks.sh --fix
  fi
fi
