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
