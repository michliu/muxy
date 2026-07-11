package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"io"
	"os"
	"os/signal"
	"syscall"

	"golang.org/x/term"
)

const detachByte = byte(0x1d)

type termData struct {
	PaneID string `json:"paneID"`
	Bytes  string `json:"bytes"`
}

func writePaneEvent(paneID string, ev eventPayload, out io.Writer) {
	if ev.Event != "terminalOutput" && ev.Event != "terminalSnapshot" {
		return
	}
	if ev.Data == nil {
		return
	}
	var td termData
	if json.Unmarshal(ev.Data.Value, &td) != nil {
		return
	}
	if td.PaneID != paneID {
		return
	}
	raw, err := base64.StdEncoding.DecodeString(td.Bytes)
	if err != nil {
		return
	}
	out.Write(raw)
}

func scanForDetach(buf []byte, detach byte) ([]byte, bool) {
	if i := bytes.IndexByte(buf, detach); i >= 0 {
		return buf[:i], true
	}
	return buf, false
}

func runAttach(ctx context.Context, client *Client, paneID string, fd int, in io.Reader, out io.Writer) error {
	cols, rows, err := term.GetSize(fd)
	if err != nil {
		cols, rows = 80, 24
	}
	if _, err := client.request(ctx, "takeOverPane", map[string]any{
		"paneID": paneID, "cols": cols, "rows": rows,
	}); err != nil {
		return err
	}

	oldState, err := term.MakeRaw(fd)
	if err != nil {
		return err
	}
	restore := func() { term.Restore(fd, oldState) }
	defer restore()

	kill := make(chan os.Signal, 1)
	signal.Notify(kill, syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP)
	go func() {
		<-kill
		restore()
		os.Exit(1)
	}()

	client.setEventSink(func(ev eventPayload) { writePaneEvent(paneID, ev, out) })
	defer client.setEventSink(nil)

	winch := make(chan os.Signal, 1)
	signal.Notify(winch, syscall.SIGWINCH)
	defer signal.Stop(winch)
	go func() {
		for range winch {
			if cols, rows, err := term.GetSize(fd); err == nil {
				client.sendInput(ctx, "terminalResize", map[string]any{
					"paneID": paneID, "cols": cols, "rows": rows,
				})
			}
		}
	}()

	buf := make([]byte, 4096)
	for {
		n, readErr := in.Read(buf)
		if n > 0 {
			before, detached := scanForDetach(buf[:n], detachByte)
			if len(before) > 0 {
				client.sendInput(ctx, "terminalInput", map[string]any{
					"paneID": paneID,
					"bytes":  base64.StdEncoding.EncodeToString(before),
				})
			}
			if detached {
				client.sendInput(ctx, "releasePane", map[string]any{"paneID": paneID})
				return nil
			}
		}
		if readErr != nil {
			return readErr
		}
	}
}
