package main

import "testing"

func TestCollectTerminalPanesNestedSplit(t *testing.T) {
	root := []byte(`{
      "type":"split","split":{"direction":"horizontal","ratio":0.6,
        "first":{"type":"tabArea","tabArea":{"activeTabID":"t1","tabs":[
          {"id":"t1","kind":"terminal","title":"zsh","paneID":"P1"},
          {"id":"t2","kind":"vcs","title":"Git","paneID":null}]}},
        "second":{"type":"split","split":{"direction":"vertical","ratio":0.5,
          "first":{"type":"tabArea","tabArea":{"activeTabID":"t3","tabs":[
            {"id":"t3","kind":"terminal","title":"top","paneID":"P2"}]}},
          "second":{"type":"tabArea","tabArea":{"activeTabID":"t4","tabs":[
            {"id":"t4","kind":"terminal","title":"log","paneID":"P3"}]}}}}}}`)
	panes, err := collectTerminalPanes(root)
	if err != nil {
		t.Fatalf("collect: %v", err)
	}
	if len(panes) != 3 {
		t.Fatalf("want 3 panes, got %d: %+v", len(panes), panes)
	}
	if panes[0].ID != "P1" || panes[0].Title != "zsh" ||
		panes[1].ID != "P2" || panes[2].ID != "P3" {
		t.Errorf("panes = %+v", panes)
	}
}

func TestCollectTerminalPanesSkipsNonTerminalAndNilPane(t *testing.T) {
	root := []byte(`{"type":"tabArea","tabArea":{"activeTabID":"a","tabs":[
      {"id":"a","kind":"vcs","title":"Git","paneID":null},
      {"id":"b","kind":"terminal","title":"","paneID":"P9"}]}}`)
	panes, err := collectTerminalPanes(root)
	if err != nil {
		t.Fatalf("collect: %v", err)
	}
	if len(panes) != 1 || panes[0].ID != "P9" || panes[0].Title != "Terminal" {
		t.Errorf("panes = %+v", panes)
	}
}
