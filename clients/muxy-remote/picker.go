package main

import (
	"bufio"
	"fmt"
	"io"
	"strconv"
	"strings"
)

func pick(prompt string, items []string, in io.Reader, out io.Writer) (int, error) {
	if len(items) == 0 {
		return -1, fmt.Errorf("%s: nothing to choose from", prompt)
	}
	if len(items) == 1 {
		return 0, nil
	}
	reader := bufio.NewReader(in)
	for {
		fmt.Fprintf(out, "%s:\n", prompt)
		for i, item := range items {
			fmt.Fprintf(out, "  %d) %s\n", i+1, item)
		}
		fmt.Fprint(out, "> ")
		line, err := reader.ReadString('\n')
		if err != nil && line == "" {
			return -1, fmt.Errorf("no selection: %w", err)
		}
		n, convErr := strconv.Atoi(strings.TrimSpace(line))
		if convErr == nil && n >= 1 && n <= len(items) {
			return n - 1, nil
		}
		fmt.Fprintln(out, "Invalid selection, try again.")
	}
}
