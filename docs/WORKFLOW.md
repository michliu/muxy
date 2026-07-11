# Muxy — Fork Workflow

Personal working guide for this fork. `main` here is fork-primary: it carries the web terminal feature and tracks the fork, not upstream.

## Remotes

| Remote | URL | Role |
| --- | --- | --- |
| `origin` | `github.com/muxy-app/muxy` | Upstream (pull updates only) |
| `fork` | `github.com/michliu/muxy` | Yours — primary; `main` tracks `fork/main` |

## Shortcuts

| Command | Does |
| --- | --- |
| `scripts/dev.sh` | Build the debug app and launch it (`--no-build` to skip the build) |
| `scripts/preview-web.sh` | Sync frontend edits into the running app's bundle (then hard-refresh the browser) |
| `scripts/verify.sh --fix` | Run `checks.sh` with the pinned lint tools on `PATH` |
| `scripts/sync-upstream.sh --check --push` | Merge `origin/main` into `main`, verify, push to fork |

## One-time setup (per machine)

```bash
scripts/setup.sh                                  # GhosttyKit.xcframework + terminfo + ghostty resources (needs gh auth to muxy-app/ghostty)
git remote add fork https://github.com/michliu/muxy.git
git branch -u fork/main main
```

Pinned lint tools: `scripts/checks.sh` enforces the exact versions in `.tool-versions` (swiftformat `0.60.1`, swiftlint `0.57.1`). Keep matching binaries on `PATH` — e.g. installed at `~/.muxy-tools/bin`.

## Build & run the dev app

```bash
swift build --product Muxy      # build (first time is slow)
.build/debug/Muxy               # run — use this, not run-dev.sh
```

`scripts/run-dev.sh` runs under a shell whose `PATH` often lacks `swift`, so it errors `command not found: swift` whenever it wants to rebuild. Running the binary directly avoids that. The app is yours to run and verify visually.

## Web terminal

- Enable: **Settings → Mobile** toggle. A "Web Terminal" card shows the URL + QR.
- Open `http://<host>:<port>` in a browser on the same LAN; approve the browser on the Mac the first time.
- Ports: dev page `4867` / ws `4866`; release `4864` / `4865`.
- Frontend live edit: `MuxyWebServer` reads files from the built bundle **per request**. To preview a CSS/JS/HTML change without rebuilding, copy it into `.build/arm64-apple-macosx/debug/Muxy_MuxyServer.bundle/web-terminal/` and hard-refresh the browser (`⌘⇧R`). Swift changes still need a rebuild.

## muxy-remote (Ubuntu/Linux CLI client)

A Go client under `clients/muxy-remote/` that attaches to a Mac terminal pane from a Linux shell over the same WebSocket server (like `ssh` / `tmux attach`). See `clients/muxy-remote/README.md`.

```bash
# build for the target Ubuntu arch (static, no cgo) and copy over
cd clients/muxy-remote
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -o muxy-remote-linux-amd64 .   # or GOARCH=arm64
scp muxy-remote-linux-amd64 you@ubuntu:~/muxy-remote

# on Ubuntu (Mac: Settings → Mobile enabled):
chmod +x ~/muxy-remote
./muxy-remote --host <mac-host> --port 4865      # release; dev is 4866
```

Reach the Mac via LAN IP, a Tailscale IP (both must be on the same tailnet), or an SSH tunnel (`ssh -L 4865:localhost:4865 …` then `--host localhost`). Tests: `cd clients/muxy-remote && go test ./...` (Go 1.26+, no SPM).

## Verify

```bash
PATH="$HOME/.muxy-tools/bin:$PATH" scripts/checks.sh --fix
```

Runs format + lint + build + full test suite (Muxy app only; `muxy-remote` has its own `go test`).

## Sync upstream + back up

```bash
scripts/sync-upstream.sh --check --push
```

Fetches `origin`, merges `origin/main` into your `main`, runs checks, pushes to `fork/main`. On merge conflicts: resolve, `git add <files>`, `git commit` — most likely `Package.swift`, `Muxy/Services/Mobile/MobileServerService.swift`, `Muxy/Views/Settings/MobileSettingsView.swift`. Flags: `--check` and `--push` are independent; omit both for a plain merge.
