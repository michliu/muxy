# Setup & Security

## Enabling the server

The Mobile server is **disabled by default**. Toggle it from **Settings → Mobile** on macOS.

| Setting | Default | Notes |
| --- | --- | --- |
| Enable Mobile Server | off | Starts/stops the WebSocket listener. |
| Port | `4865` | Stored in `UserDefaults`, applied on start. Bind failures roll the toggle back off. |
| Approved devices | empty | List of paired clients with revoke buttons. |

## Endpoint

- Protocol: WebSocket
- URL: `ws://<host>:<port>`
- Encoding: UTF-8 JSON
- Date format: ISO 8601
- IDs: UUID strings

## Security model

The API is designed for trusted local networks.

- Transport is `ws://`, **not** TLS. Once a client is attached, the live terminal byte stream — everything typed and printed — is visible to anyone sniffing the local network.
- Clients must authenticate before any other RPC, and every reconnect re-validates the device's secret token.
- New devices must be approved from the Mac before they become trusted; approvals are revocable.

For any non-trusted network, run the connection over **Tailscale** (WireGuard-encrypted end-to-end) or another VPN. Do not expose the port directly to the internet. TLS may be added in a future release without changing the wire protocol.

## Error codes

| Code | Meaning |
| --- | --- |
| `400` | Invalid parameters |
| `401` | Authentication required |
| `403` | Pairing denied |
| `404` | Resource not found |
| `408` | Pairing request timed out |
| `500` | Internal error or operation failure |

## Integration recommendations

- Persist `deviceID` and `token` securely.
- Re-authenticate after reconnecting.
- Treat `workspaceChanged` as authoritative.
- Cache project logos after decoding the Base64 payload.
- Call `attachPane` before interactive terminal use; on reconnect, try `resyncPane` first and fall back to `attachPane`.
- Handle `401` by retrying with pairing only when appropriate.
- Do not assume event filtering is enforced server-side.

See the [mobile client guide](mobile-client.md) for the full terminal implementation plan.
