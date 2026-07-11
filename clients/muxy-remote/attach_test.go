package main

import (
	"bytes"
	"testing"
)

func TestWritePaneEventDecodesMatchingPane(t *testing.T) {
	var out bytes.Buffer
	events := []eventPayload{
		{Event: "terminalSnapshot", Data: &dataBody{
			Type: "terminalSnapshot", Value: []byte(`{"paneID":"P1","bytes":"aGVsbG8="}`)}},
		{Event: "terminalOutput", Data: &dataBody{
			Type: "terminalOutput", Value: []byte(`{"paneID":"other","bytes":"eA=="}`)}},
		{Event: "terminalOutput", Data: &dataBody{
			Type: "terminalOutput", Value: []byte(`{"paneID":"P1","bytes":"IQ=="}`)}},
		{Event: "workspaceChanged", Data: &dataBody{Type: "workspace", Value: []byte(`{}`)}},
	}
	for _, ev := range events {
		writePaneEvent("P1", ev, &out)
	}

	if out.String() != "hello!" {
		t.Errorf("out = %q, want %q", out.String(), "hello!")
	}
}

func TestScanForDetach(t *testing.T) {
	before, found := scanForDetach([]byte{'a', 'b', 0x1d, 'c'}, 0x1d)
	if !found || string(before) != "ab" {
		t.Errorf("before=%q found=%v", before, found)
	}
	before, found = scanForDetach([]byte("abc"), 0x1d)
	if found || string(before) != "abc" {
		t.Errorf("before=%q found=%v", before, found)
	}
}
