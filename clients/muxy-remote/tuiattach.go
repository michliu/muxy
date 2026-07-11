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
