# Web Terminal

Muxy serves a browser client that takes over any terminal pane in real time. It reuses the same WebSocket RPC and device-pairing model as the mobile companions — the browser is just another approved device.

## How it works

- A read-only static HTTP server ships the bundled web app (`http://<host>:<webPort>`, default `4864` release / `4867` development).
- The page connects back to the WebSocket server (`ws://<host>:<port>`). Because the page is served over `http`, there is no mixed-content block.
- Enable it from **Settings → Mobile** — the same toggle that starts the mobile server also starts the web server. The panel shows the URL and a QR code (no token).

## Using it

1. Enable **Allow mobile device connections** on the Mac.
2. Open the Web Terminal URL in a browser on the same network.
3. Approve the browser on the Mac the first time (same pairing sheet as mobile).
4. Pick a project, then a terminal tab; the browser takes over that pane and streams it live.

## Security

- `http`/`ws` on the local network only — treat as trusted-LAN unless tunneled (e.g. Tailscale).
- The HTTP server is read-only, GET-only, and serves only bundled assets; it exposes no RPC and no filesystem access. The URL/QR never carry a token.
- Pane control is ownership-based: taking over a pane in the browser takes it from the Mac until released.
