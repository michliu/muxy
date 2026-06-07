# Events

Server-pushed events go to authenticated clients. Treat `workspaceChanged` as the source of truth for tab and layout updates — it covers tab create/close/select/rename, area splits, focus changes, and pin/color updates.

| Event | Data type | Description |
| --- | --- | --- |
| `workspaceChanged` | `workspace` | Full workspace tree for one project. Pushed when tabs, splits, focus, titles, or pin/color state change. One event per active project per change burst (debounced ~80 ms). |
| `terminalDetached` | `terminalDetached` | A pane the client was attached to is gone (closed tab/pane). Dismiss its terminal view. |
| `notificationReceived` | `notification` | New notification emitted by Muxy |
| `projectsChanged` | `projects` | Updated project list. Pushed when projects are added, removed, renamed, reordered, or have their icon/logo/color updated. |
| `themeChanged` | `deviceTheme` | Updated terminal foreground/background colors |

Terminal **output** is not an event — it is delivered as offset-stamped `output` [binary frames](protocol.md#terminal-binary-channel) after [`attachPane`](methods.md#terminal).

## `workspaceChanged`

Full workspace tree, keyed by `projectID + worktreeID`. See [Data Objects → Workspace](data-objects.md#workspace) for the recursive shape.
