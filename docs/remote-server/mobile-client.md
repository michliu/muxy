# Mobile Client Guide

How to build the terminal side of a mobile client against this API. The model is **SSH-like**: the desktop ships the raw PTY byte stream, your client runs its own VT emulator and renders it; input goes back as raw bytes. Sessions are **tmux-style shared** — the Mac stays live and both sides type into the same shell.

## Recommended stack

- **VT emulator: [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm).** Its `Terminal` core is headless (Foundation-only): feed bytes with `feed(...)`, and its `TerminalView` (UIKit) renders on iOS. Implement `TerminalViewDelegate.send(source:data:)` to capture keystrokes and ship them as `input` frames. Do **not** spawn a PTY on the device — the PTY lives on the Mac.
- **Transport:** one WebSocket (`URLSessionWebSocketTask` or `Network.framework`). JSON RPC on **text** frames, terminal frames on **binary** frames.
- **Discovery:** the desktop advertises Bonjour `_muxy._tcp` on the LAN. For remote, connect over Tailscale/VPN (see [Setup → Security](setup.md#security-model)).

## Connection lifecycle

1. Connect the WebSocket.
2. `authenticateDevice` → on `401`, `pairDevice` (the Mac shows an approval sheet), then persist `deviceID` + `token` in the Keychain.
3. `listProjects` → `selectProject` → `listWorktrees` / `selectWorktree` → `getWorkspace`.
4. Walk the workspace tree to the terminal `paneID` you want.

## Attaching to a terminal

1. Send `attachPane(paneID)`. The result [`terminalAttach`](data-objects.md#terminal-attach) gives `cols`, `rows`, `baseOffset`, and a `snapshot`.
2. Size the emulator to `cols`×`rows` and `feed` the `snapshot` (it paints the current screen).
3. Consume `output` [binary frames](protocol.md#terminal-binary-channel): `feed` each payload verbatim. Maintain `nextExpectedOffset = sequence + payloadLength`.
4. On keystrokes, send `input` binary frames with the raw bytes.
5. On a `resize` frame, re-size the emulator to the new host `cols`×`rows`.

## Sizing — host wins, you reflow

The Mac owns one PTY at its window size. **Never send a resize**; instead render at the host's `cols`×`rows` and fit-to-width (scale the font / allow horizontal scroll). This keeps the Mac view undistorted. The host pushes a `resize` frame whenever its window changes.

## Reconnection

The Mac session is always alive regardless of your connectivity, so reconnect is cheap:

1. On foreground / socket re-open, re-`authenticateDevice`.
2. Send `resyncPane(paneID, haveOffset: nextExpectedOffset)`.
   - Success → the host replays exactly the bytes you missed as `output` frames. Seamless.
   - `404` → you are no longer attached to a live session (e.g. its replay buffer was freed after you fully detached); call `attachPane` again and repaint from the fresh snapshot.
3. You may send `ack` frames with your `nextExpectedOffset`. They are accepted but the current host does not yet act on them, so this is optional.

Expect iOS to suspend the app in the background and drop the socket within seconds — design for reconnect-and-resync on foreground rather than holding the connection.

## Recommended enhancement: predictive local echo

Everything above feels native on Wi-Fi/Tailscale and fine on cellular. To feel *better than SSH* on a high-latency link, add **mosh-style predictive echo** on the client: when the user types a printable character, optimistically render it at the cursor immediately (underline it while unconfirmed), and reconcile when the authoritative `output` frames arrive. Make it adaptive — only predict once a prior prediction on that row was confirmed, and gate on measured round-trip time so it never flickers on a fast link or fights a full-screen app (vim, less). This is purely client-side; it needs no protocol change.

## Things to get right

- A frame payload may split a UTF-8 character or an escape sequence. Always `feed` bytes straight to the emulator and let it buffer partial sequences — never parse them yourself.
- The Mac is a co-equal writer. The cursor may jump because the desktop user typed; this is expected (tmux semantics), not a bug.
- Treat `workspaceChanged` as the source of truth for layout; dismiss a pane on `terminalDetached`.
