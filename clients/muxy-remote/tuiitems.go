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
