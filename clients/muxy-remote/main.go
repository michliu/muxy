package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"golang.org/x/term"
)

func main() {
	host := flag.String("host", "", "Muxy host (LAN IP, Tailscale IP, or localhost via SSH tunnel)")
	port := flag.Int("port", 4865, "Muxy WebSocket port (4865 release, 4866 dev)")
	flag.Parse()

	if *host == "" {
		fmt.Fprintln(os.Stderr, "error: --host is required")
		flag.Usage()
		os.Exit(2)
	}
	if err := run(*host, *port); err != nil {
		fmt.Fprintf(os.Stderr, "muxy-remote: %v\n", err)
		os.Exit(1)
	}
}

func run(host string, port int) error {
	ctx := context.Background()

	configDir, err := os.UserConfigDir()
	if err != nil {
		configDir = filepath.Join(os.Getenv("HOME"), ".config")
	}
	cr, err := loadOrCreateCreds(filepath.Join(configDir, "muxy-remote"))
	if err != nil {
		return err
	}

	url := fmt.Sprintf("ws://%s:%d", host, port)
	fmt.Fprintf(os.Stderr, "Connecting %s …\n", url)
	client, err := dial(ctx, url)
	if err != nil {
		return fmt.Errorf("connect failed (is Muxy running with Settings → Mobile enabled?): %w", err)
	}
	defer client.close()

	fmt.Fprintln(os.Stderr, "Authenticating (approve this device on your Mac if prompted) …")
	if _, err := client.authenticate(ctx, cr); err != nil {
		return fmt.Errorf("auth failed (delete ~/.config/muxy-remote to re-pair): %w", err)
	}

	projectID, err := selectProject(ctx, client)
	if err != nil {
		return err
	}
	paneID, err := selectPane(ctx, client, projectID)
	if err != nil {
		return err
	}

	fmt.Fprintln(os.Stderr, "Attached. Press Ctrl-] to detach.")
	return runAttach(ctx, client, paneID, int(os.Stdin.Fd()), os.Stdin, os.Stdout)
}

func selectProject(ctx context.Context, client *Client) (string, error) {
	value, err := client.request(ctx, "listProjects", nil)
	if err != nil {
		return "", err
	}
	var projects []struct {
		ID   string `json:"id"`
		Name string `json:"name"`
	}
	if err := json.Unmarshal(value, &projects); err != nil {
		return "", err
	}
	if len(projects) == 0 {
		return "", fmt.Errorf("no projects open in Muxy")
	}
	names := make([]string, len(projects))
	for i, p := range projects {
		names[i] = p.Name
	}
	idx, err := pick("Project", names, os.Stdin, os.Stderr)
	if err != nil {
		return "", err
	}
	projectID := projects[idx].ID
	if _, err := client.request(ctx, "selectProject", map[string]any{"projectID": projectID}); err != nil {
		return "", err
	}
	return projectID, nil
}

func selectPane(ctx context.Context, client *Client, projectID string) (string, error) {
	wtValue, err := client.request(ctx, "listWorktrees", map[string]any{"projectID": projectID})
	if err != nil {
		return "", err
	}
	var worktrees []struct {
		ID   string `json:"id"`
		Name string `json:"name"`
	}
	json.Unmarshal(wtValue, &worktrees)
	if len(worktrees) > 0 {
		wtNames := make([]string, len(worktrees))
		for i, w := range worktrees {
			wtNames[i] = w.Name
		}
		widx, err := pick("Worktree", wtNames, os.Stdin, os.Stderr)
		if err != nil {
			return "", err
		}
		if _, err := client.request(ctx, "selectWorktree", map[string]any{
			"projectID": projectID, "worktreeID": worktrees[widx].ID,
		}); err != nil {
			return "", err
		}
	}

	wsValue, err := client.request(ctx, "getWorkspace", map[string]any{"projectID": projectID})
	if err != nil {
		return "", err
	}
	var ws struct {
		Root json.RawMessage `json:"root"`
	}
	if err := json.Unmarshal(wsValue, &ws); err != nil {
		return "", err
	}
	panes, err := collectTerminalPanes(ws.Root)
	if err != nil {
		return "", err
	}
	if len(panes) == 0 {
		return "", fmt.Errorf("no terminal sessions in this project")
	}
	titles := make([]string, len(panes))
	for i, p := range panes {
		titles[i] = p.Title
	}
	idx, err := pick("Terminal session", titles, os.Stdin, os.Stderr)
	if err != nil {
		return "", err
	}
	return panes[idx].ID, nil
}

var _ = term.IsTerminal
