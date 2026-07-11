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
