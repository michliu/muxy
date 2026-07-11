# muxy-remote

Take over a Mac Muxy terminal pane from an Ubuntu terminal, like `ssh` / `tmux attach`.

## Build

    go build -o muxy-remote ./clients/muxy-remote
    scp muxy-remote you@ubuntu:~/

Single static binary, no runtime deps — works on headless servers.

## Use

On the Mac: **Settings → Mobile → enable**. Then on Ubuntu:

    ./muxy-remote --host <mac-host> [--port 4865]

First run prompts approval on the Mac. Pick a project (and a worktree if the project has several), then a terminal session; you're attached. Press **Ctrl-]** to detach.

Ports: release `4865`, dev `4866`.

## Reaching the Mac

- **Same LAN:** `--host <mac-lan-ip>`
- **Tailscale:** install on both, `--host <mac-100.x>`
- **SSH tunnel:** `ssh -L 4865:localhost:4865 you@mac` then `--host localhost`

Plaintext `ws://` — trusted networks only; tunnel anything beyond the LAN.
