# API Methods

## Projects & Workspace

| Method | Parameters | Result |
| --- | --- | --- |
| `listProjects` | none | `projects` |
| `selectProject` | `projectID` | `ok` |
| `listWorktrees` | `projectID` | `worktrees` |
| `selectWorktree` | `projectID`, `worktreeID` | `ok` |
| `getWorkspace` | `projectID` | `workspace` |
| `createTab` | `projectID`, `areaID?`, `kind` | `tab` |
| `closeTab` | `projectID`, `areaID`, `tabID` | `ok` |
| `selectTab` | `projectID`, `areaID`, `tabID` | `ok` |
| `splitArea` | `projectID`, `areaID`, `direction`, `position` | `ok` |
| `closeArea` | `projectID`, `areaID` | `ok` |
| `focusArea` | `projectID`, `areaID` | `ok` |

Enums:

- `kind`: `terminal`, `vcs`, `editor`, `diffViewer`
- `direction`: `horizontal`, `vertical`
- `position`: `first`, `second`

## Terminal

Terminal sessions use **tmux-style shared attach**, not ownership transfer. The Mac stays fully live while a client is attached; both the Mac and any attached clients type into the same shell. Input, output, and resize are [binary frames](protocol.md#terminal-binary-channel), not JSON RPC.

| Method | Parameters | Result |
| --- | --- | --- |
| `attachPane` | `paneID` | `terminalAttach` |
| `detachPane` | `paneID` | `ok` |
| `resyncPane` | `paneID`, `haveOffset` | `ok` |

Flow:

- **`attachPane`** materializes the pane if needed and returns a [`terminalAttach`](data-objects.md#terminal-attach): the host `cols`/`rows`, a `baseOffset`, and a one-time `snapshot` (raw VT bytes that paint the current screen). Paint the snapshot, then start consuming `output` binary frames whose `sequence` is at or after `baseOffset`. Returns `404` if the pane cannot be materialized.
- Send keystrokes as `input` binary frames. The host owns the terminal size: the initial size arrives in the `terminalAttach` result, and a `resize` frame is pushed whenever the Mac window changes thereafter. Render at the host size and fit-to-width on screen. Clients never resize the host.
- **`resyncPane`** is for reconnect: send the highest offset you have (`nextExpectedOffset`). The host replays the exact missed bytes as `output` frames, or — if you have been gone too long for its replay buffer — repaints the screen. Returns `404` if the pane has no live session to resync against; fall back to `attachPane` in that case.
- **`detachPane`** stops the stream. The Mac session is unaffected and keeps running.

## Notifications & visual data

| Method | Parameters | Result |
| --- | --- | --- |
| `getProjectLogo` | `projectID` | `projectLogo` |
| `listNotifications` | none | `notifications` |
| `markNotificationRead` | `notificationID` | `ok` |
| `subscribe` | `events` | `ok` |
| `unsubscribe` | `events` | `ok` |

`subscribe` / `unsubscribe` are accepted for compatibility, but clients should still be prepared to receive all broadcast event types.

## Extensions

| Method | Parameters | Result |
| --- | --- | --- |
| `extensionRequest` | `extension`, `action`, `payload` | `extensionResult` |

`extensionRequest` proxies a call to an installed extension that serves the named `action`. `payload` and the `extensionResult.payload` are arbitrary JSON. The desktop resolves the handler, prompts the user for consent, runs it in the extension's background script, and returns its value. Errors: `404` (unknown extension or undeclared action), `403` (extension lacks `remote:serve` or consent denied), `503` (extension not running), `502` (handler failed), `504` (handler timed out). See [extension remote methods](../extensions/remote-methods.md).

## Git & worktrees

| Method | Parameters | Result |
| --- | --- | --- |
| `getVCSStatus` | `projectID` | `vcsStatus` |
| `vcsRefresh` | `projectID` | `vcsStatus` |
| `vcsCommit` | `projectID`, `message`, `stageAll` | `ok` |
| `vcsPush` | `projectID` | `ok` |
| `vcsPull` | `projectID` | `ok` |
| `vcsStageFiles` | `projectID`, `paths` | `ok` |
| `vcsUnstageFiles` | `projectID`, `paths` | `ok` |
| `vcsDiscardFiles` | `projectID`, `paths`, `untrackedPaths` | `ok` |
| `vcsListBranches` | `projectID` | `vcsBranches` |
| `vcsSwitchBranch` | `projectID`, `branch` | `ok` |
| `vcsCreateBranch` | `projectID`, `name` | `ok` |
| `vcsCreatePR` | `projectID`, `title`, `body`, `baseBranch`, `draft` | `vcsPRCreated` |
| `vcsMergePullRequest` | `projectID`, `number`, `method`, `deleteBranch` | `ok` |
| `vcsAddWorktree` | `projectID`, `name`, `branch`, `createBranch` | `worktrees` |
| `vcsRemoveWorktree` | `projectID`, `worktreeID` | `ok` |

`getVCSStatus` and `vcsListBranches` read from the desktop's in-memory VCS cache instead of running git on every call. The cache is lazily populated on first access per worktree and kept fresh by the desktop's file-system watcher and post-mutation notifications. Clients can call `vcsRefresh` at any time to force a full re-read from git; it awaits completion and returns the fresh `vcsStatus`.

## Example: full authentication request

```json
{
  "type": "request",
  "payload": {
    "id": "1",
    "method": "authenticateDevice",
    "params": {
      "type": "authenticateDevice",
      "value": {
        "deviceID": "2f8d1f9f-e065-4f62-af30-8c4b3d0bfc53",
        "deviceName": "Android Client",
        "token": "random-secret-token"
      }
    }
  }
}
```
