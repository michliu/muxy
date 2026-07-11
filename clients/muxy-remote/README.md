# muxy-remote

Take over a Mac Muxy terminal pane from an Ubuntu terminal, like `ssh` / `tmux attach`.

## Build

    go build -o muxy-remote ./clients/muxy-remote
    scp muxy-remote you@ubuntu:~/

Single static binary, no runtime deps — works on headless servers.

## Use

On the Mac: **Settings → Mobile → enable**. Then on Ubuntu:

    ./muxy-remote --host <mac-host> [--port 4865]

On a real terminal this opens a **session browser** (a searchable TUI):

- `↑/↓` or `j/k` move · `/` search · `Enter` attach · `Esc` back · `q` quit
- Sessions refresh live; markers show `●` your session, `▣` held by the Mac, `○` held by another client
- While attached it's a full raw terminal — press **Ctrl-]** to detach back to the browser and pick another session

Piped/non-interactive input falls back to a numbered menu. Ports: release `4865`, dev `4866`.

## Reaching the Mac

- **Same LAN:** `--host <mac-lan-ip>`
- **Tailscale:** install on both, `--host <mac-100.x>`
- **SSH tunnel:** `ssh -L 4865:localhost:4865 you@mac` then `--host localhost`

Plaintext `ws://` — trusted networks only; tunnel anything beyond the LAN.
