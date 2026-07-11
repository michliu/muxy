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
func (i projItem) Description() string { return "" }
func (i projItem) FilterValue() string { return i.info.Name }

type wtItem struct{ info worktreeInfo }

func (i wtItem) Title() string       { return i.info.Name }
func (i wtItem) Description() string { return "" }
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

// TEMP stub — replaced by tuiattach.go in the next task
func attachCmd(deps *tuiDeps, paneID string) tea.Cmd { return nil }
