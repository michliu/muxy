#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

USE_MERGE=false
RUN_CHECKS=false
DO_PUSH=false
FORK_REMOTE="${MUXY_FORK_REMOTE:-fork}"
for arg in "$@"; do
  case "$arg" in
    --merge) USE_MERGE=true ;;
    --check) RUN_CHECKS=true ;;
    --push) DO_PUSH=true ;;
    -h | --help)
      echo "Usage: scripts/sync-upstream.sh [--merge] [--check] [--push]"
      echo "  --merge   Merge main into the current branch instead of rebasing"
      echo "  --check   Run scripts/checks.sh --fix after a successful sync"
      echo "  --push    Back up the branch to your fork remote '$FORK_REMOTE' (force-with-lease)"
      echo "            Override the remote name with MUXY_FORK_REMOTE=<name>"
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

if [[ "$DO_PUSH" == true ]]; then
  if ! git remote get-url "$FORK_REMOTE" >/dev/null 2>&1; then
    echo "" >&2
    echo "No remote named '$FORK_REMOTE'. Add your fork first, e.g.:" >&2
    echo "  gh repo fork muxy-app/muxy --remote --remote-name $FORK_REMOTE --clone=false" >&2
    echo "  # or: git remote add $FORK_REMOTE https://github.com/<you>/muxy.git" >&2
    exit 1
  fi
  echo "==> Backing up '$BRANCH' to '$FORK_REMOTE' (force-with-lease)"
  git push --force-with-lease "$FORK_REMOTE" "$BRANCH"
  echo "==> Backed up to '$FORK_REMOTE/$BRANCH'"
fi
