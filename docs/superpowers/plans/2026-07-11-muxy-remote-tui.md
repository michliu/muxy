# muxy-remote TUI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Bubble Tea session browser to `muxy-remote` — searchable project/worktree/session lists, live-refreshing session list with ownership markers, and `Enter` to attach via the existing raw passthrough (`Ctrl-]` returns to the browser to switch panes).

**Architecture:** One Bubble Tea program under `clients/muxy-remote/` with a three-screen state machine (projects → worktrees → sessions). Attaching hands the terminal to the existing `runAttach` via `tea.Exec` (Bubble Tea releases/restores the terminal — no VT emulation). The client's swappable event sink forwards `workspaceChanged`/`paneOwnershipChanged` to the program while browsing, and switches to stdout writes during attach. On a tty the TUI is default; non-tty falls back to the existing number-menu flow.

**Tech Stack:** Go 1.26, `github.com/charmbracelet/bubbletea`, `github.com/charmbracelet/bubbles/list`, `github.com/charmbracelet/lipgloss`. Reuses existing `client.go` / `workspace.go` / `attach.go` / `creds.go` / `picker.go`.

## Global Constraints

- Package `main` under `clients/muxy-remote/`. No new Muxy server RPC. Reuse: `listProjects`, `selectProject`, `listWorktrees`, `selectWorktree`, `getWorkspace`, `takeOverPane`, `releasePane`, `terminalInput`, `terminalResize`, plus events `workspaceChanged`, `paneOwnershipChanged`, `terminalOutput`, `terminalSnapshot`.
- Attach is always full-screen raw passthrough via `runAttach` (no VT emulator). Detach key stays `Ctrl-]`.
- TUI is used only when `term.IsTerminal(int(os.Stdin.Fd()))`; otherwise the existing number-menu flow runs unchanged.
- Ownership markers are best-effort from live `paneOwnershipChanged` events plus the client's own attached pane (no startup query RPC exists).
- Every exit path restores the terminal (Bubble Tea manages alt-screen; `runAttach` manages raw mode + signals).
- Run `gofmt -w` and `go vet ./...` before each commit; all `go test ./...` green (Go 1.26+).

---

## File Structure

Under `clients/muxy-remote/`:

- `tuiitems.go` — pure list-item types + builders (`sessionItem`, `makeSessionItems`, `parsePaneOwnership`)
- `tui.go` — the Bubble Tea `browserModel` (screens, list, Update, View) + `runTUI` entry
- `tuiattach.go` — the `tea.Exec` attach command wrapping `runAttach` + sink toggling
- `main.go` (modify) — tty gate: `runTUI` on a tty, number-menu otherwise
- `*_test.go` — tests for the pure builders and model data methods
- `README.md` (modify) — document the TUI + keys + non-tty fallback

---

## Task 1: Pure list-item types + ownership parsing

**Files:**
- Create: `clients/muxy-remote/tuiitems.go`
- Test: `clients/muxy-remote/tuiitems_test.go`

**Interfaces:**
- Consumes: `Pane` (from `workspace.go`), `eventPayload`/`dataBody` (from `protocol.go`).
- Produces:
  - `type sessionItem struct { PaneID string; Name string; Owner string }` with methods `Title() string`, `Description() string`, `FilterValue() string` (satisfies `bubbles/list.DefaultItem`). `Owner` is `""` | `"self"` | `"mac"` | `"other"`; `Title()` prefixes a marker (`● ` self, `▣ ` mac, `○ ` other, none for empty).
  - `makeSessionItems(panes []Pane, owners map[string]string, attached string) []sessionItem`.
  - `parsePaneOwnership(value json.RawMessage) (paneID string, owner string, ok bool)` — decodes a `paneOwnershipChanged` value `{paneID, owner:{mac:{…}}|{remote:{…}}}`; returns owner `"mac"` or `"other"`.

- [ ] **Step 1: Add TUI deps**

Run: `cd clients/muxy-remote && go get github.com/charmbracelet/bubbletea github.com/charmbracelet/bubbles github.com/charmbracelet/lipgloss`
Expected: `go.mod`/`go.sum` updated.

- [ ] **Step 2: Write the failing test**

`clients/muxy-remote/tuiitems_test.go`:

```go
package main

import "testing"

func TestMakeSessionItemsMarkers(t *testing.T) {
	panes := []Pane{{ID: "P1", Title: "zsh"}, {ID: "P2", Title: "top"}, {ID: "P3", Title: "log"}}
	owners := map[string]string{"P2": "mac", "P3": "other"}
	items := makeSessionItems(panes, owners, "P1")
	if len(items) != 3 {
		t.Fatalf("len = %d", len(items))
	}
	if items[0].Owner != "self" || items[1].Owner != "mac" || items[2].Owner != "other" {
		t.Fatalf("owners = %+v", items)
	}
	if items[0].Title() != "● zsh" {
		t.Errorf("self title = %q", items[0].Title())
	}
	if items[1].Title() != "▣ top" {
		t.Errorf("mac title = %q", items[1].Title())
	}
	if items[0].FilterValue() != "zsh" {
		t.Errorf("filter = %q", items[0].FilterValue())
	}
}

func TestParsePaneOwnershipMac(t *testing.T) {
	paneID, owner, ok := parsePaneOwnership([]byte(`{"paneID":"P9","owner":{"mac":{"deviceName":"Mac"}}}`))
	if !ok || paneID != "P9" || owner != "mac" {
		t.Fatalf("paneID=%q owner=%q ok=%v", paneID, owner, ok)
	}
}

func TestParsePaneOwnershipRemoteIsOther(t *testing.T) {
	_, owner, ok := parsePaneOwnership([]byte(`{"paneID":"P9","owner":{"remote":{"deviceID":"d","deviceName":"Other"}}}`))
	if !ok || owner != "other" {
		t.Fatalf("owner=%q ok=%v", owner, ok)
	}
}

func TestParsePaneOwnershipMalformed(t *testing.T) {
	if _, _, ok := parsePaneOwnership([]byte(`not json`)); ok {
		t.Error("want ok=false")
	}
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd clients/muxy-remote && go test -run 'TestMakeSessionItems|TestParsePaneOwnership' ./...`
Expected: FAIL — `undefined: makeSessionItems`.

- [ ] **Step 4: Implement**

`clients/muxy-remote/tuiitems.go`:

```go
package main

import "encoding/json"

type sessionItem struct {
	PaneID string
	Name   string
	Owner  string
}

func (s sessionItem) Title() string {
	switch s.Owner {
	case "self":
		return "● " + s.Name
	case "mac":
		return "▣ " + s.Name
	case "other":
		return "○ " + s.Name
	default:
		return s.Name
	}
}

func (s sessionItem) Description() string { return s.PaneID }
func (s sessionItem) FilterValue() string { return s.Name }

func makeSessionItems(panes []Pane, owners map[string]string, attached string) []sessionItem {
	items := make([]sessionItem, 0, len(panes))
	for _, p := range panes {
		owner := owners[p.ID]
		if p.ID == attached {
			owner = "self"
		}
		items = append(items, sessionItem{PaneID: p.ID, Name: p.Title, Owner: owner})
	}
	return items
}

func parsePaneOwnership(value json.RawMessage) (string, string, bool) {
	var v struct {
		PaneID string `json:"paneID"`
		Owner  struct {
			Mac    json.RawMessage `json:"mac"`
			Remote json.RawMessage `json:"remote"`
		} `json:"owner"`
	}
	if json.Unmarshal(value, &v) != nil || v.PaneID == "" {
		return "", "", false
	}
	if len(v.Owner.Mac) > 0 {
		return v.PaneID, "mac", true
	}
	if len(v.Owner.Remote) > 0 {
		return v.PaneID, "other", true
	}
	return v.PaneID, "", true
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd clients/muxy-remote && go test ./... && go vet ./...`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
gofmt -w clients/muxy-remote/tuiitems.go clients/muxy-remote/tuiitems_test.go
git add clients/muxy-remote/tuiitems.go clients/muxy-remote/tuiitems_test.go clients/muxy-remote/go.mod clients/muxy-remote/go.sum
git commit -m "feat(muxy-remote): TUI list items and ownership parsing"
```

---

## Task 2: Browser model — screens, live refresh, ownership

**Files:**
- Create: `clients/muxy-remote/tui.go`
- Test: `clients/muxy-remote/tui_test.go`

**Interfaces:**
- Consumes: `sessionItem`/`makeSessionItems`/`parsePaneOwnership` (Task 1), `Pane`/`collectTerminalPanes` (workspace.go), `eventPayload` (protocol.go), `Client` (client.go).
- Produces:
  - message types `wsEventMsg{ Ep eventPayload }`, `attachDoneMsg{ Err error }`, `dataErrMsg{ Err error }`, `worktreesLoadedMsg{ Items []worktreeInfo }`, `workspaceLoadedMsg{ Root json.RawMessage }`.
  - `type projectInfo struct{ ID, Name string }`, `type worktreeInfo struct{ ID, Name string }`.
  - `browserModel` (Bubble Tea model) with data methods `applyWorkspace(root json.RawMessage)` (rebuild session items, preserve the selected paneID) and `applyOwnership(paneID, owner string)` (update owners map + rebuild).
  - `newBrowserModel(deps *tuiDeps, projects []projectInfo) browserModel`.
  - `type tuiDeps struct { Ctx context.Context; Client *Client; BrowseSink func(eventPayload) }` (BrowseSink filled by `runTUI` in Task 3).

- [ ] **Step 1: Write the failing test**

`clients/muxy-remote/tui_test.go`:

```go
package main

import (
	"encoding/json"
	"testing"
)

func newTestModel() browserModel {
	m := newBrowserModel(&tuiDeps{}, []projectInfo{{ID: "p1", Name: "proj"}})
	m.screen = screenSessions
	m.width, m.height = 80, 24
	return m
}

func TestApplyWorkspaceBuildsSessions(t *testing.T) {
	m := newTestModel()
	root := json.RawMessage(`{"type":"tabArea","tabArea":{"activeTabID":"t1","tabs":[
		{"id":"t1","kind":"terminal","title":"zsh","paneID":"P1"},
		{"id":"t2","kind":"terminal","title":"top","paneID":"P2"}]}}`)
	m.applyWorkspace(root)
	if len(m.sessions) != 2 || m.sessions[0].PaneID != "P1" || m.sessions[1].PaneID != "P2" {
		t.Fatalf("sessions = %+v", m.sessions)
	}
}

func TestApplyOwnershipMarksPane(t *testing.T) {
	m := newTestModel()
	root := json.RawMessage(`{"type":"tabArea","tabArea":{"activeTabID":"t1","tabs":[
		{"id":"t1","kind":"terminal","title":"zsh","paneID":"P1"}]}}`)
	m.applyWorkspace(root)
	m.applyOwnership("P1", "other")
	if m.sessions[0].Owner != "other" {
		t.Fatalf("owner = %q", m.sessions[0].Owner)
	}
}

func TestApplyWorkspaceKeepsAttachedSelfMarker(t *testing.T) {
	m := newTestModel()
	m.attached = "P2"
	root := json.RawMessage(`{"type":"tabArea","tabArea":{"activeTabID":"t1","tabs":[
		{"id":"t1","kind":"terminal","title":"zsh","paneID":"P1"},
		{"id":"t2","kind":"terminal","title":"top","paneID":"P2"}]}}`)
	m.applyWorkspace(root)
	if m.sessions[1].Owner != "self" {
		t.Fatalf("attached owner = %q", m.sessions[1].Owner)
	}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd clients/muxy-remote && go test -run 'TestApply' ./...`
Expected: FAIL — `undefined: newBrowserModel`.

- [ ] **Step 3: Implement**

`clients/muxy-remote/tui.go`:

```go
package main

import (
	"context"
	"encoding/json"

	"github.com/charmbracelet/bubbles/list"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type screen int

const (
	screenProjects screen = iota
	screenWorktrees
	screenSessions
)

type projectInfo struct{ ID, Name string }
type worktreeInfo struct{ ID, Name string }

type projItem struct{ info projectInfo }

func (i projItem) Title() string       { return i.info.Name }
func (i projItem) Description() string  { return "" }
func (i projItem) FilterValue() string { return i.info.Name }

type wtItem struct{ info worktreeInfo }

func (i wtItem) Title() string       { return i.info.Name }
func (i wtItem) Description() string  { return "" }
func (i wtItem) FilterValue() string { return i.info.Name }

type tuiDeps struct {
	Ctx        context.Context
	Client     *Client
	BrowseSink func(eventPayload)
}

type wsEventMsg struct{ Ep eventPayload }
type attachDoneMsg struct{ Err error }
type dataErrMsg struct{ Err error }
type worktreesLoadedMsg struct{ Items []worktreeInfo }
type workspaceLoadedMsg struct{ Root json.RawMessage }

type browserModel struct {
	deps       *tuiDeps
	screen     screen
	list       list.Model
	projects   []projectInfo
	worktrees  []worktreeInfo
	projectID  string
	worktreeID string
	sessions   []sessionItem
	owners     map[string]string
	attached   string
	status     string
	width      int
	height     int
	quitErr    error
}

var footerStyle = lipgloss.NewStyle().Faint(true)

func newBrowserModel(deps *tuiDeps, projects []projectInfo) browserModel {
	items := make([]list.Item, len(projects))
	for i, p := range projects {
		items[i] = projItem{info: p}
	}
	l := list.New(items, list.NewDefaultDelegate(), 0, 0)
	l.Title = "Projects"
	l.SetShowHelp(true)
	return browserModel{
		deps:     deps,
		screen:   screenProjects,
		list:     l,
		projects: projects,
		owners:   map[string]string{},
	}
}

func (m *browserModel) applyWorkspace(root json.RawMessage) {
	panes, err := collectTerminalPanes(root)
	if err != nil {
		return
	}
	m.sessions = makeSessionItems(panes, m.owners, m.attached)
	if m.screen == screenSessions {
		selected := ""
		if it, ok := m.list.SelectedItem().(sessionItem); ok {
			selected = it.PaneID
		}
		m.setSessionItems(selected)
	}
}

func (m *browserModel) applyOwnership(paneID, owner string) {
	if owner == "" {
		delete(m.owners, paneID)
	} else {
		m.owners[paneID] = owner
	}
	for i := range m.sessions {
		if m.sessions[i].PaneID == paneID {
			if m.sessions[i].PaneID == m.attached {
				break
			}
			m.sessions[i].Owner = owner
		}
	}
	if m.screen == screenSessions {
		selected := ""
		if it, ok := m.list.SelectedItem().(sessionItem); ok {
			selected = it.PaneID
		}
		m.setSessionItems(selected)
	}
}

func (m *browserModel) setSessionItems(selectPaneID string) {
	items := make([]list.Item, len(m.sessions))
	idx := 0
	for i, s := range m.sessions {
		items[i] = s
		if s.PaneID == selectPaneID {
			idx = i
		}
	}
	m.list.SetItems(items)
	m.list.Select(idx)
}

func (m browserModel) Init() tea.Cmd { return nil }

func (m browserModel) loadWorktrees(projectID string) tea.Cmd {
	return func() tea.Msg {
		if _, err := m.deps.Client.request(m.deps.Ctx, "selectProject", map[string]any{"projectID": projectID}); err != nil {
			return dataErrMsg{err}
		}
		value, err := m.deps.Client.request(m.deps.Ctx, "listWorktrees", map[string]any{"projectID": projectID})
		if err != nil {
			return dataErrMsg{err}
		}
		var raw []struct {
			ID   string `json:"id"`
			Name string `json:"name"`
		}
		json.Unmarshal(value, &raw)
		items := make([]worktreeInfo, len(raw))
		for i, w := range raw {
			items[i] = worktreeInfo{ID: w.ID, Name: w.Name}
		}
		return worktreesLoadedMsg{items}
	}
}

func (m browserModel) loadWorkspace(projectID, worktreeID string) tea.Cmd {
	return func() tea.Msg {
		if worktreeID != "" {
			if _, err := m.deps.Client.request(m.deps.Ctx, "selectWorktree", map[string]any{
				"projectID": projectID, "worktreeID": worktreeID,
			}); err != nil {
				return dataErrMsg{err}
			}
		}
		value, err := m.deps.Client.request(m.deps.Ctx, "getWorkspace", map[string]any{"projectID": projectID})
		if err != nil {
			return dataErrMsg{err}
		}
		var ws struct {
			Root json.RawMessage `json:"root"`
		}
		json.Unmarshal(value, &ws)
		return workspaceLoadedMsg{ws.Root}
	}
}

func (m browserModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		m.list.SetSize(msg.Width, msg.Height-1)
		return m, nil

	case wsEventMsg:
		ep := msg.Ep
		if ep.Data == nil {
			return m, nil
		}
		switch ep.Event {
		case "workspaceChanged":
			m.applyWorkspace(ep.Data.Value)
		case "paneOwnershipChanged":
			if paneID, owner, ok := parsePaneOwnership(ep.Data.Value); ok {
				m.applyOwnership(paneID, owner)
			}
		}
		return m, nil

	case worktreesLoadedMsg:
		m.worktrees = msg.Items
		if len(msg.Items) <= 1 {
			wtID := ""
			if len(msg.Items) == 1 {
				wtID = msg.Items[0].ID
			}
			m.worktreeID = wtID
			m.screen = screenSessions
			m.status = ""
			return m, m.loadWorkspace(m.projectID, wtID)
		}
		items := make([]list.Item, len(msg.Items))
		for i, w := range msg.Items {
			items[i] = wtItem{info: w}
		}
		m.screen = screenWorktrees
		m.list.SetItems(items)
		m.list.Select(0)
		m.list.Title = "Worktrees"
		return m, nil

	case workspaceLoadedMsg:
		m.applyWorkspace(msg.Root)
		m.screen = screenSessions
		m.list.Title = "Sessions"
		m.setSessionItems(m.attached)
		return m, nil

	case attachDoneMsg:
		m.deps.Client.setEventSink(m.deps.BrowseSink)
		if msg.Err != nil {
			m.status = "disconnected: " + msg.Err.Error()
			return m, tea.Quit
		}
		return m, m.loadWorkspace(m.projectID, m.worktreeID)

	case dataErrMsg:
		m.quitErr = msg.Err
		return m, tea.Quit

	case tea.KeyMsg:
		if m.list.FilterState() == list.Filtering {
			break
		}
		switch msg.String() {
		case "ctrl+c", "q":
			return m, tea.Quit
		case "esc":
			return m.goBack()
		case "enter":
			return m.onEnter()
		}
	}

	var cmd tea.Cmd
	m.list, cmd = m.list.Update(msg)
	return m, cmd
}

func (m browserModel) goBack() (tea.Model, tea.Cmd) {
	switch m.screen {
	case screenSessions:
		items := make([]list.Item, len(m.worktrees))
		for i, w := range m.worktrees {
			items[i] = wtItem{info: w}
		}
		if len(m.worktrees) > 1 {
			m.screen = screenWorktrees
			m.list.SetItems(items)
			m.list.Title = "Worktrees"
			return m, nil
		}
		fallthrough
	case screenWorktrees:
		items := make([]list.Item, len(m.projects))
		for i, p := range m.projects {
			items[i] = projItem{info: p}
		}
		m.screen = screenProjects
		m.list.SetItems(items)
		m.list.Title = "Projects"
		return m, nil
	}
	return m, nil
}

func (m browserModel) onEnter() (tea.Model, tea.Cmd) {
	switch m.screen {
	case screenProjects:
		it, ok := m.list.SelectedItem().(projItem)
		if !ok {
			return m, nil
		}
		m.projectID = it.info.ID
		m.status = "loading…"
		return m, m.loadWorktrees(it.info.ID)
	case screenWorktrees:
		it, ok := m.list.SelectedItem().(wtItem)
		if !ok {
			return m, nil
		}
		m.worktreeID = it.info.ID
		m.status = "loading…"
		return m, m.loadWorkspace(m.projectID, it.info.ID)
	case screenSessions:
		it, ok := m.list.SelectedItem().(sessionItem)
		if !ok {
			return m, nil
		}
		m.attached = it.PaneID
		return m, attachCmd(m.deps, it.PaneID)
	}
	return m, nil
}

func (m browserModel) View() string {
	footer := m.status
	if footer == "" {
		footer = "enter attach · / search · esc back · q quit"
	}
	return m.list.View() + "\n" + footerStyle.Render(footer)
}
```

> Note: `attachCmd(deps, paneID)` is defined in Task 3 (`tuiattach.go`). Until Task 3 lands, `go build` of the package fails on that reference — that is expected; this task's tests run via `go test` which compiles the test binary the same way, so Task 2 must be committed together with a stub or Task 3 must follow immediately. To keep Task 2 self-contained, add a temporary stub at the end of `tui.go` and delete it in Task 3:
> ```go
> // TEMP stub — replaced by tuiattach.go in the next task
> func attachCmd(deps *tuiDeps, paneID string) tea.Cmd { return nil }
> ```

- [ ] **Step 4: Run to verify it passes**

Run: `cd clients/muxy-remote && go test ./... && go vet ./...`
Expected: PASS (the `applyWorkspace`/`applyOwnership` tests).

- [ ] **Step 5: Commit**

```bash
gofmt -w clients/muxy-remote/tui.go clients/muxy-remote/tui_test.go
git add clients/muxy-remote/tui.go clients/muxy-remote/tui_test.go
git commit -m "feat(muxy-remote): TUI browser model with live refresh and ownership"
```

---

## Task 3: Attach command (tea.Exec) + sink toggling + runTUI

**Files:**
- Create: `clients/muxy-remote/tuiattach.go`
- Modify: `clients/muxy-remote/tui.go` (delete the TEMP `attachCmd` stub)

**Interfaces:**
- Consumes: `runAttach` (attach.go), `Client` (client.go), `tuiDeps`/`browserModel`/`attachDoneMsg`/`newBrowserModel`/`projectInfo` (tui.go).
- Produces:
  - `attachCmd(deps *tuiDeps, paneID string) tea.Cmd` — returns `tea.Exec(...)` that runs `runAttach` and yields `attachDoneMsg`.
  - `runTUI(ctx context.Context, client *Client) error` — loads projects, builds the model, installs the browse sink, runs the program.

- [ ] **Step 1: Delete the TEMP stub in tui.go**

Remove the `// TEMP stub` block (the temporary `func attachCmd(...)` in `tui.go`).

- [ ] **Step 2: Implement tuiattach.go**

`clients/muxy-remote/tuiattach.go`:

```go
package main

import (
	"context"
	"encoding/json"
	"io"
	"os"

	tea "github.com/charmbracelet/bubbletea"
)

type execAttach struct {
	deps   *tuiDeps
	paneID string
}

func (e *execAttach) SetStdin(io.Reader)  {}
func (e *execAttach) SetStdout(io.Writer) {}
func (e *execAttach) SetStderr(io.Writer) {}

func (e *execAttach) Run() error {
	err := runAttach(e.deps.Ctx, e.deps.Client, e.paneID, int(os.Stdin.Fd()), os.Stdin, os.Stdout)
	e.deps.Client.setEventSink(e.deps.BrowseSink)
	return err
}

func attachCmd(deps *tuiDeps, paneID string) tea.Cmd {
	return tea.Exec(&execAttach{deps: deps, paneID: paneID}, func(err error) tea.Msg {
		return attachDoneMsg{Err: err}
	})
}

func runTUI(ctx context.Context, client *Client) error {
	value, err := client.request(ctx, "listProjects", nil)
	if err != nil {
		return err
	}
	var raw []struct {
		ID   string `json:"id"`
		Name string `json:"name"`
	}
	if err := json.Unmarshal(value, &raw); err != nil {
		return err
	}
	projects := make([]projectInfo, len(raw))
	for i, p := range raw {
		projects[i] = projectInfo{ID: p.ID, Name: p.Name}
	}

	deps := &tuiDeps{Ctx: ctx, Client: client}
	m := newBrowserModel(deps, projects)
	p := tea.NewProgram(m, tea.WithAltScreen())
	deps.BrowseSink = func(ep eventPayload) { p.Send(wsEventMsg{Ep: ep}) }
	client.setEventSink(deps.BrowseSink)

	final, err := p.Run()
	if err != nil {
		return err
	}
	if fm, ok := final.(browserModel); ok && fm.quitErr != nil {
		return fm.quitErr
	}
	return nil
}
```

- [ ] **Step 3: Build + test + vet**

Run: `cd clients/muxy-remote && go build -o /tmp/muxy-remote . && go test ./... && go vet ./...`
Expected: build succeeds; tests pass.

- [ ] **Step 4: Commit**

```bash
gofmt -w clients/muxy-remote/tuiattach.go clients/muxy-remote/tui.go
git add clients/muxy-remote/tuiattach.go clients/muxy-remote/tui.go
git commit -m "feat(muxy-remote): tea.Exec attach handoff and runTUI entry"
```

---

## Task 4: tty gate in main + README

**Files:**
- Modify: `clients/muxy-remote/main.go`
- Modify: `clients/muxy-remote/README.md`

**Interfaces:**
- Consumes: `runTUI` (Task 3), existing number-menu flow (`selectProject`/`selectPane`/`runAttach`).

- [ ] **Step 1: Gate on tty in run()**

In `clients/muxy-remote/main.go`, after the `authenticate` block and before `stdin := bufio.NewReader(os.Stdin)`, insert:

```go
	if term.IsTerminal(int(os.Stdin.Fd())) {
		return runTUI(ctx, client)
	}
```

Ensure `golang.org/x/term` is imported in main.go (it already provides `term.IsTerminal`; if main.go doesn't import it yet, add `"golang.org/x/term"` to the import block and remove any now-unused placeholder such as `var _ = term.IsTerminal`).

- [ ] **Step 2: Build + smoke**

Run: `cd clients/muxy-remote && go build -o /tmp/muxy-remote . && /tmp/muxy-remote 2>&1 | head -2`
Expected: build OK; running with no `--host` prints `error: --host is required` and exits 2 (unchanged).

- [ ] **Step 3: Full test + vet**

Run: `cd clients/muxy-remote && go test ./... && go vet ./...`
Expected: PASS.

- [ ] **Step 4: Update README**

In `clients/muxy-remote/README.md`, replace the "## Use" section body with:

```markdown
On the Mac: **Settings → Mobile → enable**. Then on Ubuntu:

    ./muxy-remote --host <mac-host> [--port 4865]

On a real terminal this opens a **session browser** (a searchable TUI):

- `↑/↓` or `j/k` move · `/` search · `Enter` attach · `Esc` back · `q` quit
- Sessions refresh live; markers show `●` your session, `▣` held by the Mac, `○` held by another client
- While attached it's a full raw terminal — press **Ctrl-]** to detach back to the browser and pick another session

Piped/non-interactive input falls back to a numbered menu. Ports: release `4865`, dev `4866`.
```

- [ ] **Step 5: Commit**

```bash
gofmt -w clients/muxy-remote/main.go
git add clients/muxy-remote/main.go clients/muxy-remote/README.md
git commit -m "feat(muxy-remote): default to TUI on a tty, number-menu fallback"
```

---

## Task 5: Final build + manual verification

- [ ] **Step 1: Cross-compile check**

Run: `cd clients/muxy-remote && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -o /tmp/mr-linux . && echo OK`
Expected: `OK` (Linux static binary builds with the TUI deps).

- [ ] **Step 2: Manual attach (user, against live Muxy on a real terminal)**

With Muxy running (Settings → Mobile enabled), on a real terminal:

```
./muxy-remote --host <host> --port 4865
```

Verify: project list → (worktree list if >1) → session browser; `/` filters; `Enter` attaches (screen shows the remote terminal, typing works); `Ctrl-]` returns to the browser with the cursor on that session; open a new terminal on the Mac and confirm it appears in the list live; `Esc` goes back a screen; `q` quits and the terminal is restored (not left in raw/alt-screen).

- [ ] **Step 3: Commit any fixes from manual testing**

```bash
git add -A && git commit -m "fix(muxy-remote): address TUI manual-test findings"
```

---

## Self-Review

- **Spec coverage:** items+ownership (Task 1), browser model with screens/live-refresh/ownership (Task 2), tea.Exec attach handoff + sink toggling + runTUI (Task 3), tty gate + number-menu fallback + README (Task 4), cross-build + manual (Task 5). All spec sections covered.
- **Placeholders:** none — the only non-final code is the explicitly-labeled TEMP `attachCmd` stub in Task 2, removed in Task 3 Step 1 (a sequenced hand-off, not a TBD).
- **Type consistency:** `sessionItem{PaneID,Name,Owner}` + `makeSessionItems(panes,owners,attached)` + `parsePaneOwnership` (Task 1) consumed in Task 2; `tuiDeps{Ctx,Client,BrowseSink}`, `browserModel`, `attachDoneMsg{Err}`, `newBrowserModel(deps,projects)`, `projectInfo{ID,Name}` (Task 2) consumed by `attachCmd`/`runTUI` (Task 3); `runTUI(ctx, client)` (Task 3) called from `main.go` (Task 4). Signatures match across tasks.
