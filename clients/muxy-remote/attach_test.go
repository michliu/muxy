package main

import (
	"bytes"
	"testing"
	"time"
)

func TestPumpOutputDecodesMatchingPane(t *testing.T) {
	events := make(chan eventPayload, 4)
	done := make(chan struct{})
	var out bytes.Buffer

	events <- eventPayload{Event: "terminalSnapshot", Data: &dataBody{
		Type: "terminalSnapshot", Value: []byte(`{"paneID":"P1","bytes":"aGVsbG8="}`)}}
	events <- eventPayload{Event: "terminalOutput", Data: &dataBody{
		Type: "terminalOutput", Value: []byte(`{"paneID":"other","bytes":"eA=="}`)}}
	events <- eventPayload{Event: "terminalOutput", Data: &dataBody{
		Type: "terminalOutput", Value: []byte(`{"paneID":"P1","bytes":"IQ=="}`)}}

	go pumpOutput("P1", events, &out, done)
	time.Sleep(100 * time.Millisecond)
	close(done)

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
