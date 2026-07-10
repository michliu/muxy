#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

RUN_CHECKS=false
DO_PUSH=false
FORK_REMOTE="${MUXY_FORK_REMOTE:-fork}"
for arg in "$@"; do
  case "$arg" in
    --check) RUN_CHECKS=true ;;
    --push) DO_PUSH=true ;;
    -h | --help)
      echo "Usage: scripts/sync-upstream.sh [--check] [--push]"
      echo "  Merges upstream origin/main into your fork-primary 'main'."
      echo "  --check   Run scripts/checks.sh --fix after a successful merge"
      echo "  --push    Push 'main' to your fork remote '$FORK_REMOTE'"
      echo "            Override the remote name with MUXY_FORK_REMOTE=<name>"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree has uncommitted changes. Commit or stash them first." >&2
  exit 1
fi

START_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

echo "==> Fetching origin"
git fetch origin

echo "==> Merging origin/main into main"
git checkout main
if ! git merge origin/main; then
  echo ""
  echo "Merge conflicts. Resolve them, then: git add <files> && git commit"
  echo "Likely files: Package.swift, MobileServerService.swift, MobileSettingsView.swift"
  exit 1
fi

echo "==> 'main' now includes the latest origin/main"

if [[ "$RUN_CHECKS" == true ]]; then
  echo "==> Running checks"
  if [[ -d "$HOME/.muxy-tools/bin" ]]; then
    PATH="$HOME/.muxy-tools/bin:$PATH" scripts/checks.sh --fix
  else
    scripts/checks.sh --fix
  fi
fi

if [[ "$DO_PUSH" == true ]]; then
  if ! git remote get-url "$FORK_REMOTE" >/dev/null 2>&1; then
    echo "" >&2
    echo "No remote named '$FORK_REMOTE'. Add your fork first, e.g.:" >&2
    echo "  git remote add $FORK_REMOTE https://github.com/<you>/muxy.git" >&2
    exit 1
  fi
  echo "==> Pushing 'main' to '$FORK_REMOTE'"
  git push "$FORK_REMOTE" main
  echo "==> Pushed to '$FORK_REMOTE/main'"
fi

if [[ "$START_BRANCH" != "main" && "$START_BRANCH" != "HEAD" ]]; then
  git checkout "$START_BRANCH"
fi
