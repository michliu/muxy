package main

import "encoding/json"

type Pane struct {
	ID    string
	Title string
}

type tabDTO struct {
	Kind   string  `json:"kind"`
	Title  string  `json:"title"`
	PaneID *string `json:"paneID"`
}

type splitNode struct {
	Type    string `json:"type"`
	TabArea *struct {
		Tabs []tabDTO `json:"tabs"`
	} `json:"tabArea"`
	Split *struct {
		First  json.RawMessage `json:"first"`
		Second json.RawMessage `json:"second"`
	} `json:"split"`
}

func collectTerminalPanes(root json.RawMessage) ([]Pane, error) {
	var panes []Pane
	if err := walkNode(root, &panes); err != nil {
		return nil, err
	}
	return panes, nil
}

func walkNode(raw json.RawMessage, out *[]Pane) error {
	if len(raw) == 0 {
		return nil
	}
	var node splitNode
	if err := json.Unmarshal(raw, &node); err != nil {
		return err
	}
	switch node.Type {
	case "tabArea":
		if node.TabArea == nil {
			return nil
		}
		for _, tab := range node.TabArea.Tabs {
			if tab.Kind != "terminal" || tab.PaneID == nil {
				continue
			}
			title := tab.Title
			if title == "" {
				title = "Terminal"
			}
			*out = append(*out, Pane{ID: *tab.PaneID, Title: title})
		}
	case "split":
		if node.Split == nil {
			return nil
		}
		if err := walkNode(node.Split.First, out); err != nil {
			return err
		}
		if err := walkNode(node.Split.Second, out); err != nil {
			return err
		}
	}
	return nil
}
