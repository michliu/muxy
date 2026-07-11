package main

import (
	"bufio"
	"bytes"
	"strings"
	"testing"
)

func TestPickReadsNumber(t *testing.T) {
	var out bytes.Buffer
	idx, err := pick("Project", []string{"a", "b", "c"}, bufio.NewReader(strings.NewReader("2\n")), &out)
	if err != nil {
		t.Fatalf("pick: %v", err)
	}
	if idx != 1 {
		t.Errorf("idx = %d, want 1", idx)
	}
}

func TestPickSingleItemAutoSelects(t *testing.T) {
	var out bytes.Buffer
	idx, err := pick("Project", []string{"only"}, bufio.NewReader(strings.NewReader("")), &out)
	if err != nil || idx != 0 {
		t.Fatalf("idx=%d err=%v", idx, err)
	}
}

func TestPickReprompt(t *testing.T) {
	var out bytes.Buffer
	idx, err := pick("Project", []string{"a", "b"}, bufio.NewReader(strings.NewReader("9\nx\n1\n")), &out)
	if err != nil {
		t.Fatalf("pick: %v", err)
	}
	if idx != 0 {
		t.Errorf("idx = %d, want 0", idx)
	}
}

func TestPickNoItems(t *testing.T) {
	var out bytes.Buffer
	_, err := pick("Project", nil, bufio.NewReader(strings.NewReader("")), &out)
	if err == nil {
		t.Error("want error for empty items")
	}
}
