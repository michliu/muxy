# muxy-remote Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Go single-binary CLI that connects to Muxy's WebSocket server from Ubuntu and takes over a Mac terminal pane with raw passthrough (like `ssh`/`tmux attach`).

**Architecture:** One Go `package main` under `clients/muxy-remote/`. Pure protocol/workspace/creds/picker logic is unit-tested; the WS client is tested against a fake in-process server; the raw-tty attach loop is split so its pumps are unit-tested and only the terminal wiring is manual. Reuses Muxy's existing WS RPC — no server changes.

**Tech Stack:** Go 1.26, `github.com/coder/websocket`, `golang.org/x/term`, `github.com/google/uuid`, stdlib `encoding/json`.

## Global Constraints

- Module lives at `clients/muxy-remote/` with its own `go.mod` (module `github.com/michliu/muxy/clients/muxy-remote`); NOT part of SPM.
- No new Muxy server RPC. Reuse: `authenticateDevice`, `pairDevice`, `listProjects`, `selectProject`, `listWorktrees`, `selectWorktree`, `getWorkspace`, `takeOverPane`, `releasePane`, `terminalInput`, `terminalResize`.
- Wire protocol (verbatim): request `{"type":"request","payload":{"id","method","params"}}` where `params={"type":<method>,"value":<v>}` or `null`; response `payload.result.value` | `payload.error{code,message}`; event `payload.event`+`payload.data.value`; `terminalOutput`/`terminalSnapshot` value `{paneID, bytes(base64)}`. `terminalInput` is fire-and-forget (no response).
- Default port `4865` (release WS); dev is `4866`.
- Detach key: `Ctrl-]` (byte `0x1d`).
- Creds persist at `~/.config/muxy-remote/config.json` as `{deviceID, token}`.
- Every exit path must restore the tty (no leftover raw mode).
- Run `gofmt -w` on changed files and `go vet ./...` before each commit; all `go test ./...` green.

---

## File Structure

Under `clients/muxy-remote/`:

- `go.mod` — module + deps
- `protocol.go` — envelope encode/decode + RPC types
- `workspace.go` — walk `SplitNodeDTO`, collect terminal panes
- `creds.go` — deviceID/token load-or-create + deviceName
- `client.go` — WS dial, request/response correlation, event dispatch, `authenticate`
- `picker.go` — number-menu selection
- `attach.go` — output/input pumps + raw-tty attach wiring
- `main.go` — flags + orchestration
- `*_test.go` — per-unit tests
- `README.md` — build + three connection methods

---

## Task 1: Module scaffold + protocol envelope

**Files:**
- Create: `clients/muxy-remote/go.mod`
- Create: `clients/muxy-remote/protocol.go`
- Test: `clients/muxy-remote/protocol_test.go`

**Interfaces:**
- Produces: `encodeRequest(id, method string, value any) ([]byte, error)`; `decodeIncoming([]byte) (*incoming, error)`; types `incoming{Type string; Payload json.RawMessage}`, `responsePayload{ID string; Result *resultBody; Error *rpcError}`, `resultBody{Type string; Value json.RawMessage}`, `eventPayload{Event string; Data *dataBody}`, `dataBody{Type string; Value json.RawMessage}`, `rpcError{Code int; Message string}` (implements `error`).

- [ ] **Step 1: go.mod**

`clients/muxy-remote/go.mod`:

```
module github.com/michliu/muxy/clients/muxy-remote

go 1.26
```

- [ ] **Step 2: Write the failing test**

`clients/muxy-remote/protocol_test.go`:

```go
package main

import (
	"encoding/json"
	"testing"
)

func TestEncodeRequestWithValue(t *testing.T) {
	data, err := encodeRequest("7", "getWorkspace", map[string]string{"projectID": "p1"})
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	var m map[string]any
	if err := json.Unmarshal(data, &m); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if m["type"] != "request" {
		t.Errorf("type = %v", m["type"])
	}
	payload := m["payload"].(map[string]any)
	if payload["id"] != "7" || payload["method"] != "getWorkspace" {
		t.Errorf("payload = %v", payload)
	}
	params := payload["params"].(map[string]any)
	if params["type"] != "getWorkspace" {
		t.Errorf("params.type = %v", params["type"])
	}
	value := params["value"].(map[string]any)
	if value["projectID"] != "p1" {
		t.Errorf("value = %v", value)
	}
}

func TestEncodeRequestNilValueIsNullParams(t *testing.T) {
	data, err := encodeRequest("1", "listProjects", nil)
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	var m map[string]any
	json.Unmarshal(data, &m)
	payload := m["payload"].(map[string]any)
	if payload["params"] != nil {
		t.Errorf("params should be null, got %v", payload["params"])
	}
}

func TestDecodeIncomingResponse(t *testing.T) {
	raw := `{"type":"response","payload":{"id":"3","result":{"type":"ok","value":null}}}`
	in, err := decodeIncoming([]byte(raw))
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	if in.Type != "response" {
		t.Fatalf("type = %s", in.Type)
	}
	var rp responsePayload
	if err := json.Unmarshal(in.Payload, &rp); err != nil {
		t.Fatalf("payload: %v", err)
	}
	if rp.ID != "3" || rp.Result == nil || rp.Result.Type != "ok" {
		t.Errorf("rp = %+v", rp)
	}
}

func TestDecodeIncomingEvent(t *testing.T) {
	raw := `{"type":"event","payload":{"event":"terminalOutput","data":{"type":"terminalOutput","value":{"paneID":"x","bytes":"aGk="}}}}`
	in, err := decodeIncoming([]byte(raw))
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	var ep eventPayload
	json.Unmarshal(in.Payload, &ep)
	if ep.Event != "terminalOutput" || ep.Data == nil {
		t.Fatalf("ep = %+v", ep)
	}
}

func TestRPCErrorImplementsError(t *testing.T) {
	var err error = &rpcError{Code: 401, Message: "Authentication required"}
	if err.Error() == "" {
		t.Error("empty error string")
	}
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd clients/muxy-remote && go test ./...`
Expected: FAIL — `undefined: encodeRequest` etc.

- [ ] **Step 4: Implement**

`clients/muxy-remote/protocol.go`:

```go
package main

import (
	"encoding/json"
	"fmt"
)

type params struct {
	Type  string `json:"type"`
	Value any    `json:"value"`
}

type requestEnvelope struct {
	Type    string `json:"type"`
	Payload struct {
		ID     string  `json:"id"`
		Method string  `json:"method"`
		Params *params `json:"params"`
	} `json:"payload"`
}

func encodeRequest(id, method string, value any) ([]byte, error) {
	var env requestEnvelope
	env.Type = "request"
	env.Payload.ID = id
	env.Payload.Method = method
	if value != nil {
		env.Payload.Params = &params{Type: method, Value: value}
	}
	return json.Marshal(env)
}

type incoming struct {
	Type    string          `json:"type"`
	Payload json.RawMessage `json:"payload"`
}

func decodeIncoming(data []byte) (*incoming, error) {
	var in incoming
	if err := json.Unmarshal(data, &in); err != nil {
		return nil, err
	}
	return &in, nil
}

type rpcError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

func (e *rpcError) Error() string {
	return fmt.Sprintf("rpc error %d: %s", e.Code, e.Message)
}

type resultBody struct {
	Type  string          `json:"type"`
	Value json.RawMessage `json:"value"`
}

type responsePayload struct {
	ID     string      `json:"id"`
	Result *resultBody `json:"result"`
	Error  *rpcError   `json:"error"`
}

type dataBody struct {
	Type  string          `json:"type"`
	Value json.RawMessage `json:"value"`
}

type eventPayload struct {
	Event string    `json:"event"`
	Data  *dataBody `json:"data"`
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd clients/muxy-remote && go test ./... && go vet ./...`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
gofmt -w clients/muxy-remote/*.go
git add clients/muxy-remote/go.mod clients/muxy-remote/protocol.go clients/muxy-remote/protocol_test.go
git commit -m "feat(muxy-remote): protocol envelope encode/decode"
```

---

## Task 2: Workspace tree walk

**Files:**
- Create: `clients/muxy-remote/workspace.go`
- Test: `clients/muxy-remote/workspace_test.go`

**Interfaces:**
- Produces: `type Pane struct { ID string; Title string }`; `collectTerminalPanes(root json.RawMessage) ([]Pane, error)`.

- [ ] **Step 1: Write the failing test**

`clients/muxy-remote/workspace_test.go`:

```go
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd clients/muxy-remote && go test -run TestCollectTerminalPanes ./...`
Expected: FAIL — `undefined: collectTerminalPanes`.

- [ ] **Step 3: Implement**

`clients/muxy-remote/workspace.go`:

```go
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
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd clients/muxy-remote && go test ./... && go vet ./...`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
gofmt -w clients/muxy-remote/workspace.go clients/muxy-remote/workspace_test.go
git add clients/muxy-remote/workspace.go clients/muxy-remote/workspace_test.go
git commit -m "feat(muxy-remote): collect terminal panes from workspace tree"
```

---

## Task 3: Credentials (deviceID/token) persistence

**Files:**
- Create: `clients/muxy-remote/creds.go`
- Test: `clients/muxy-remote/creds_test.go`

**Interfaces:**
- Produces: `type creds struct { DeviceID string; Token string }`; `loadOrCreateCreds(dir string) (creds, error)`; `deviceName() string`.

- [ ] **Step 1: Add uuid dep**

Run: `cd clients/muxy-remote && go get github.com/google/uuid`
Expected: `go.mod`/`go.sum` updated.

- [ ] **Step 2: Write the failing test**

`clients/muxy-remote/creds_test.go`:

```go
package main

import (
	"testing"
)

func TestLoadOrCreateCredsPersistsAndReloads(t *testing.T) {
	dir := t.TempDir()
	first, err := loadOrCreateCreds(dir)
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	if first.DeviceID == "" || first.Token == "" {
		t.Fatalf("empty creds: %+v", first)
	}
	second, err := loadOrCreateCreds(dir)
	if err != nil {
		t.Fatalf("reload: %v", err)
	}
	if second.DeviceID != first.DeviceID || second.Token != first.Token {
		t.Errorf("creds changed on reload: %+v vs %+v", second, first)
	}
}

func TestDeviceNameNonEmpty(t *testing.T) {
	if deviceName() == "" {
		t.Error("deviceName empty")
	}
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd clients/muxy-remote && go test -run 'TestLoadOrCreateCreds|TestDeviceName' ./...`
Expected: FAIL — `undefined: loadOrCreateCreds`.

- [ ] **Step 4: Implement**

`clients/muxy-remote/creds.go`:

```go
package main

import (
	"encoding/json"
	"os"
	"path/filepath"

	"github.com/google/uuid"
)

type creds struct {
	DeviceID string `json:"deviceID"`
	Token    string `json:"token"`
}

func loadOrCreateCreds(dir string) (creds, error) {
	path := filepath.Join(dir, "config.json")
	data, err := os.ReadFile(path)
	if err == nil {
		var c creds
		if err := json.Unmarshal(data, &c); err == nil && c.DeviceID != "" && c.Token != "" {
			return c, nil
		}
	}
	c := creds{
		DeviceID: uuid.NewString(),
		Token:    uuid.NewString() + uuid.NewString(),
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return creds{}, err
	}
	out, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return creds{}, err
	}
	if err := os.WriteFile(path, out, 0o600); err != nil {
		return creds{}, err
	}
	return c, nil
}

func deviceName() string {
	host, err := os.Hostname()
	if err != nil || host == "" {
		host = "ubuntu"
	}
	return "muxy-remote (" + host + ")"
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd clients/muxy-remote && go test ./... && go vet ./...`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
gofmt -w clients/muxy-remote/creds.go clients/muxy-remote/creds_test.go
git add clients/muxy-remote/creds.go clients/muxy-remote/creds_test.go clients/muxy-remote/go.mod clients/muxy-remote/go.sum
git commit -m "feat(muxy-remote): persist device credentials"
```

---

## Task 4: WS client — dial, request/response correlation, event dispatch

**Files:**
- Create: `clients/muxy-remote/client.go`
- Test: `clients/muxy-remote/client_test.go`

**Interfaces:**
- Consumes: `encodeRequest`, `decodeIncoming`, `responsePayload`, `eventPayload`, `rpcError`.
- Produces: `type Client struct{...}`; `dial(ctx context.Context, url string) (*Client, error)`; `(*Client) request(ctx context.Context, method string, value any) (json.RawMessage, error)` (returns `result.value`; returns `*rpcError` on error payload); `(*Client) sendInput(ctx context.Context, method string, value any) error` (fire-and-forget, no wait); `(*Client) events() <-chan eventPayload`; `(*Client) close()`.

- [ ] **Step 1: Add websocket dep**

Run: `cd clients/muxy-remote && go get github.com/coder/websocket`
Expected: `go.mod`/`go.sum` updated.

- [ ] **Step 2: Write the failing test**

`clients/muxy-remote/client_test.go`:

```go
package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"
)

func fakeServer(t *testing.T, handle func(ctx context.Context, c *websocket.Conn)) string {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		c, err := websocket.Accept(w, r, nil)
		if err != nil {
			return
		}
		c.SetReadLimit(1 << 20)
		ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
		defer cancel()
		handle(ctx, c)
	}))
	t.Cleanup(srv.Close)
	return "ws" + strings.TrimPrefix(srv.URL, "http")
}

func TestRequestReturnsResultValue(t *testing.T) {
	url := fakeServer(t, func(ctx context.Context, c *websocket.Conn) {
		_, data, err := c.Read(ctx)
		if err != nil {
			return
		}
		in, _ := decodeIncoming(data)
		var rp struct {
			Payload struct {
				ID string `json:"id"`
			} `json:"payload"`
		}
		json.Unmarshal(append([]byte(`{"payload":`), append(in.Payload, '}')...), &rp)
		resp := `{"type":"response","payload":{"id":"` + rp.Payload.ID +
			`","result":{"type":"projects","value":[{"id":"p1"}]}}}`
		c.Write(ctx, websocket.MessageText, []byte(resp))
	})

	ctx := context.Background()
	client, err := dial(ctx, url)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer client.close()

	value, err := client.request(ctx, "listProjects", nil)
	if err != nil {
		t.Fatalf("request: %v", err)
	}
	var projects []map[string]string
	json.Unmarshal(value, &projects)
	if len(projects) != 1 || projects[0]["id"] != "p1" {
		t.Errorf("projects = %v", projects)
	}
}

func TestRequestReturnsRPCError(t *testing.T) {
	url := fakeServer(t, func(ctx context.Context, c *websocket.Conn) {
		_, data, _ := c.Read(ctx)
		in, _ := decodeIncoming(data)
		var rp struct {
			Payload struct {
				ID string `json:"id"`
			} `json:"payload"`
		}
		json.Unmarshal(append([]byte(`{"payload":`), append(in.Payload, '}')...), &rp)
		resp := `{"type":"response","payload":{"id":"` + rp.Payload.ID +
			`","error":{"code":401,"message":"nope"}}}`
		c.Write(ctx, websocket.MessageText, []byte(resp))
	})
	ctx := context.Background()
	client, _ := dial(ctx, url)
	defer client.close()

	_, err := client.request(ctx, "listProjects", nil)
	rerr, ok := err.(*rpcError)
	if !ok || rerr.Code != 401 {
		t.Fatalf("want rpcError 401, got %v", err)
	}
}

func TestEventsDelivered(t *testing.T) {
	url := fakeServer(t, func(ctx context.Context, c *websocket.Conn) {
		ev := `{"type":"event","payload":{"event":"terminalOutput","data":{"type":"terminalOutput","value":{"paneID":"x","bytes":"aGk="}}}}`
		c.Write(ctx, websocket.MessageText, []byte(ev))
		time.Sleep(200 * time.Millisecond)
	})
	ctx := context.Background()
	client, _ := dial(ctx, url)
	defer client.close()

	select {
	case ev := <-client.events():
		if ev.Event != "terminalOutput" {
			t.Errorf("event = %s", ev.Event)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("no event received")
	}
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd clients/muxy-remote && go test -run 'TestRequest|TestEvents' ./...`
Expected: FAIL — `undefined: dial`.

- [ ] **Step 4: Implement**

`clients/muxy-remote/client.go`:

```go
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"sync"

	"github.com/coder/websocket"
)

type Client struct {
	conn    *websocket.Conn
	mu      sync.Mutex
	nextID  int
	pending map[string]chan responsePayload
	eventCh chan eventPayload
	closeCh chan struct{}
}

func dial(ctx context.Context, url string) (*Client, error) {
	conn, _, err := websocket.Dial(ctx, url, nil)
	if err != nil {
		return nil, err
	}
	conn.SetReadLimit(16 << 20)
	c := &Client{
		conn:    conn,
		pending: make(map[string]chan responsePayload),
		eventCh: make(chan eventPayload, 64),
		closeCh: make(chan struct{}),
	}
	go c.readLoop()
	return c, nil
}

func (c *Client) readLoop() {
	for {
		_, data, err := c.conn.Read(context.Background())
		if err != nil {
			close(c.closeCh)
			return
		}
		in, err := decodeIncoming(data)
		if err != nil {
			continue
		}
		switch in.Type {
		case "response":
			var rp responsePayload
			if json.Unmarshal(in.Payload, &rp) != nil {
				continue
			}
			c.mu.Lock()
			ch := c.pending[rp.ID]
			delete(c.pending, rp.ID)
			c.mu.Unlock()
			if ch != nil {
				ch <- rp
			}
		case "event":
			var ep eventPayload
			if json.Unmarshal(in.Payload, &ep) != nil {
				continue
			}
			select {
			case c.eventCh <- ep:
			default:
			}
		}
	}
}

func (c *Client) allocID() string {
	c.mu.Lock()
	c.nextID++
	id := strconv.Itoa(c.nextID)
	c.mu.Unlock()
	return id
}

func (c *Client) request(ctx context.Context, method string, value any) (json.RawMessage, error) {
	id := c.allocID()
	frame, err := encodeRequest(id, method, value)
	if err != nil {
		return nil, err
	}
	ch := make(chan responsePayload, 1)
	c.mu.Lock()
	c.pending[id] = ch
	c.mu.Unlock()

	if err := c.conn.Write(ctx, websocket.MessageText, frame); err != nil {
		c.mu.Lock()
		delete(c.pending, id)
		c.mu.Unlock()
		return nil, err
	}

	select {
	case rp := <-ch:
		if rp.Error != nil {
			return nil, rp.Error
		}
		if rp.Result == nil {
			return nil, nil
		}
		return rp.Result.Value, nil
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-c.closeCh:
		return nil, fmt.Errorf("connection closed")
	}
}

func (c *Client) sendInput(ctx context.Context, method string, value any) error {
	frame, err := encodeRequest(c.allocID(), method, value)
	if err != nil {
		return err
	}
	return c.conn.Write(ctx, websocket.MessageText, frame)
}

func (c *Client) events() <-chan eventPayload {
	return c.eventCh
}

func (c *Client) close() {
	c.conn.Close(websocket.StatusNormalClosure, "")
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd clients/muxy-remote && go test ./... && go vet ./...`
Expected: PASS (all tests).

- [ ] **Step 6: Commit**

```bash
gofmt -w clients/muxy-remote/client.go clients/muxy-remote/client_test.go
git add clients/muxy-remote/client.go clients/muxy-remote/client_test.go clients/muxy-remote/go.mod clients/muxy-remote/go.sum
git commit -m "feat(muxy-remote): websocket client with request/response and events"
```

---

## Task 5: Authentication + pairing flow

**Files:**
- Modify: `clients/muxy-remote/client.go` (add `authenticate` method)
- Test: `clients/muxy-remote/auth_test.go`

**Interfaces:**
- Consumes: `(*Client).request`, `creds`, `deviceName`, `rpcError`.
- Produces: `(*Client) authenticate(ctx context.Context, c creds) (json.RawMessage, error)` — calls `authenticateDevice`; on `*rpcError` code `401` falls back to `pairDevice`; returns the `pairing` result value or the error.

- [ ] **Step 1: Write the failing test**

`clients/muxy-remote/auth_test.go`:

```go
package main

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/coder/websocket"
)

func readMethod(t *testing.T, ctx context.Context, c *websocket.Conn) (string, string) {
	t.Helper()
	_, data, err := c.Read(ctx)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	var env struct {
		Payload struct {
			ID     string `json:"id"`
			Method string `json:"method"`
		} `json:"payload"`
	}
	json.Unmarshal(data, &env)
	return env.Payload.ID, env.Payload.Method
}

func TestAuthenticateFallsBackToPair(t *testing.T) {
	url := fakeServer(t, func(ctx context.Context, c *websocket.Conn) {
		id, method := readMethod(t, ctx, c)
		if method != "authenticateDevice" {
			t.Errorf("first method = %s", method)
		}
		c.Write(ctx, websocket.MessageText, []byte(
			`{"type":"response","payload":{"id":"`+id+`","error":{"code":401,"message":"unknown"}}}`))
		id2, method2 := readMethod(t, ctx, c)
		if method2 != "pairDevice" {
			t.Errorf("second method = %s", method2)
		}
		c.Write(ctx, websocket.MessageText, []byte(
			`{"type":"response","payload":{"id":"`+id2+`","result":{"type":"pairing","value":{"clientID":"cid"}}}}`))
		time.Sleep(100 * time.Millisecond)
	})
	ctx := context.Background()
	client, _ := dial(ctx, url)
	defer client.close()

	value, err := client.authenticate(ctx, creds{DeviceID: "d", Token: "t"})
	if err != nil {
		t.Fatalf("authenticate: %v", err)
	}
	var pairing map[string]string
	json.Unmarshal(value, &pairing)
	if pairing["clientID"] != "cid" {
		t.Errorf("pairing = %v", pairing)
	}
}

func TestAuthenticateWrongTokenReturns403(t *testing.T) {
	url := fakeServer(t, func(ctx context.Context, c *websocket.Conn) {
		id, _ := readMethod(t, ctx, c)
		c.Write(ctx, websocket.MessageText, []byte(
			`{"type":"response","payload":{"id":"`+id+`","error":{"code":403,"message":"denied"}}}`))
		time.Sleep(100 * time.Millisecond)
	})
	ctx := context.Background()
	client, _ := dial(ctx, url)
	defer client.close()

	_, err := client.authenticate(ctx, creds{DeviceID: "d", Token: "t"})
	rerr, ok := err.(*rpcError)
	if !ok || rerr.Code != 403 {
		t.Fatalf("want 403, got %v", err)
	}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd clients/muxy-remote && go test -run TestAuthenticate ./...`
Expected: FAIL — `client.authenticate undefined`.

- [ ] **Step 3: Implement (append to client.go)**

Add to `clients/muxy-remote/client.go`:

```go
func (c *Client) authenticate(ctx context.Context, cr creds) (json.RawMessage, error) {
	value := map[string]any{
		"deviceID":   cr.DeviceID,
		"deviceName": deviceName(),
		"token":      cr.Token,
		"theme":      nil,
	}
	result, err := c.request(ctx, "authenticateDevice", value)
	if err == nil {
		return result, nil
	}
	rerr, ok := err.(*rpcError)
	if !ok || rerr.Code != 401 {
		return nil, err
	}
	return c.request(ctx, "pairDevice", value)
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd clients/muxy-remote && go test ./... && go vet ./...`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
gofmt -w clients/muxy-remote/client.go clients/muxy-remote/auth_test.go
git add clients/muxy-remote/client.go clients/muxy-remote/auth_test.go
git commit -m "feat(muxy-remote): authenticate with pairing fallback"
```

---

## Task 6: Number-menu picker

**Files:**
- Create: `clients/muxy-remote/picker.go`
- Test: `clients/muxy-remote/picker_test.go`

**Interfaces:**
- Produces: `pick(prompt string, items []string, in io.Reader, out io.Writer) (int, error)` — returns 0 immediately if exactly one item; otherwise prints a numbered list and reads a 1-based selection, re-prompting on invalid input; returns `-1, error` if no items.

- [ ] **Step 1: Write the failing test**

`clients/muxy-remote/picker_test.go`:

```go
package main

import (
	"bytes"
	"strings"
	"testing"
)

func TestPickReadsNumber(t *testing.T) {
	var out bytes.Buffer
	idx, err := pick("Project", []string{"a", "b", "c"}, strings.NewReader("2\n"), &out)
	if err != nil {
		t.Fatalf("pick: %v", err)
	}
	if idx != 1 {
		t.Errorf("idx = %d, want 1", idx)
	}
}

func TestPickSingleItemAutoSelects(t *testing.T) {
	var out bytes.Buffer
	idx, err := pick("Project", []string{"only"}, strings.NewReader(""), &out)
	if err != nil || idx != 0 {
		t.Fatalf("idx=%d err=%v", idx, err)
	}
}

func TestPickReprompt(t *testing.T) {
	var out bytes.Buffer
	idx, err := pick("Project", []string{"a", "b"}, strings.NewReader("9\nx\n1\n"), &out)
	if err != nil {
		t.Fatalf("pick: %v", err)
	}
	if idx != 0 {
		t.Errorf("idx = %d, want 0", idx)
	}
}

func TestPickNoItems(t *testing.T) {
	var out bytes.Buffer
	_, err := pick("Project", nil, strings.NewReader(""), &out)
	if err == nil {
		t.Error("want error for empty items")
	}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd clients/muxy-remote && go test -run TestPick ./...`
Expected: FAIL — `undefined: pick`.

- [ ] **Step 3: Implement**

`clients/muxy-remote/picker.go`:

```go
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
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd clients/muxy-remote && go test ./... && go vet ./...`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
gofmt -w clients/muxy-remote/picker.go clients/muxy-remote/picker_test.go
git add clients/muxy-remote/picker.go clients/muxy-remote/picker_test.go
git commit -m "feat(muxy-remote): number-menu picker"
```

---

## Task 7: Attach pumps (output/input) + raw-tty wiring

**Files:**
- Create: `clients/muxy-remote/attach.go`
- Test: `clients/muxy-remote/attach_test.go`

**Interfaces:**
- Consumes: `eventPayload`, `Client`.
- Produces:
  - `pumpOutput(paneID string, events <-chan eventPayload, out io.Writer, done <-chan struct{})` — for each `terminalOutput`/`terminalSnapshot` event whose `value.paneID == paneID`, base64-decode `value.bytes` and write to `out`; returns when `done` closes.
  - `scanForDetach(buf []byte, detach byte) (before []byte, found bool)` — returns the bytes before the first `detach` byte and whether it was present.
  - `runAttach(ctx, client *Client, paneID string, fd int, in io.Reader, out io.Writer) error` — raw-tty wiring (manual test only).
- `detachByte = byte(0x1d)`.

- [ ] **Step 1: Add term dep**

Run: `cd clients/muxy-remote && go get golang.org/x/term`
Expected: `go.mod`/`go.sum` updated.

- [ ] **Step 2: Write the failing test**

`clients/muxy-remote/attach_test.go`:

```go
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
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd clients/muxy-remote && go test -run 'TestPumpOutput|TestScanForDetach' ./...`
Expected: FAIL — `undefined: pumpOutput`.

- [ ] **Step 4: Implement**

`clients/muxy-remote/attach.go`:

```go
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

func pumpOutput(paneID string, events <-chan eventPayload, out io.Writer, done <-chan struct{}) {
	for {
		select {
		case <-done:
			return
		case ev, ok := <-events:
			if !ok {
				return
			}
			if ev.Event != "terminalOutput" && ev.Event != "terminalSnapshot" {
				continue
			}
			if ev.Data == nil {
				continue
			}
			var td termData
			if json.Unmarshal(ev.Data.Value, &td) != nil {
				continue
			}
			if td.PaneID != paneID {
				continue
			}
			raw, err := base64.StdEncoding.DecodeString(td.Bytes)
			if err != nil {
				continue
			}
			out.Write(raw)
		}
	}
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

	done := make(chan struct{})
	defer close(done)
	go pumpOutput(paneID, client.events(), out, done)

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
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd clients/muxy-remote && go test ./... && go vet ./...`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
gofmt -w clients/muxy-remote/attach.go clients/muxy-remote/attach_test.go
git add clients/muxy-remote/attach.go clients/muxy-remote/attach_test.go clients/muxy-remote/go.mod clients/muxy-remote/go.sum
git commit -m "feat(muxy-remote): attach pumps and raw-tty wiring"
```

---

## Task 8: main orchestration + README

**Files:**
- Create: `clients/muxy-remote/main.go`
- Create: `clients/muxy-remote/README.md`

**Interfaces:**
- Consumes: everything above.
- Produces: the `muxy-remote` command.

This task has no automated tests (it wires I/O, real WS, and the tty together). Verify by `go build` and a manual run against a live Muxy. Keep all logic in the tested units; `main.go` only orchestrates.

- [ ] **Step 1: Implement main.go**

`clients/muxy-remote/main.go`:

```go
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"golang.org/x/term"
)

func main() {
	host := flag.String("host", "", "Muxy host (LAN IP, Tailscale IP, or localhost via SSH tunnel)")
	port := flag.Int("port", 4865, "Muxy WebSocket port (4865 release, 4866 dev)")
	flag.Parse()

	if *host == "" {
		fmt.Fprintln(os.Stderr, "error: --host is required")
		flag.Usage()
		os.Exit(2)
	}
	if err := run(*host, *port); err != nil {
		fmt.Fprintf(os.Stderr, "muxy-remote: %v\n", err)
		os.Exit(1)
	}
}

func run(host string, port int) error {
	ctx := context.Background()

	configDir, err := os.UserConfigDir()
	if err != nil {
		configDir = filepath.Join(os.Getenv("HOME"), ".config")
	}
	cr, err := loadOrCreateCreds(filepath.Join(configDir, "muxy-remote"))
	if err != nil {
		return err
	}

	url := fmt.Sprintf("ws://%s:%d", host, port)
	fmt.Fprintf(os.Stderr, "Connecting %s …\n", url)
	client, err := dial(ctx, url)
	if err != nil {
		return fmt.Errorf("connect failed (is Muxy running with Settings → Mobile enabled?): %w", err)
	}
	defer client.close()

	fmt.Fprintln(os.Stderr, "Authenticating (approve this device on your Mac if prompted) …")
	if _, err := client.authenticate(ctx, cr); err != nil {
		return fmt.Errorf("auth failed (delete ~/.config/muxy-remote to re-pair): %w", err)
	}

	projectID, err := selectProject(ctx, client)
	if err != nil {
		return err
	}
	paneID, err := selectPane(ctx, client, projectID)
	if err != nil {
		return err
	}

	fmt.Fprintln(os.Stderr, "Attached. Press Ctrl-] to detach.")
	return runAttach(ctx, client, paneID, int(os.Stdin.Fd()), os.Stdin, os.Stdout)
}

func selectProject(ctx context.Context, client *Client) (string, error) {
	value, err := client.request(ctx, "listProjects", nil)
	if err != nil {
		return "", err
	}
	var projects []struct {
		ID   string `json:"id"`
		Name string `json:"name"`
	}
	if err := json.Unmarshal(value, &projects); err != nil {
		return "", err
	}
	if len(projects) == 0 {
		return "", fmt.Errorf("no projects open in Muxy")
	}
	names := make([]string, len(projects))
	for i, p := range projects {
		names[i] = p.Name
	}
	idx, err := pick("Project", names, os.Stdin, os.Stderr)
	if err != nil {
		return "", err
	}
	projectID := projects[idx].ID
	if _, err := client.request(ctx, "selectProject", map[string]any{"projectID": projectID}); err != nil {
		return "", err
	}
	return projectID, nil
}

func selectPane(ctx context.Context, client *Client, projectID string) (string, error) {
	wtValue, err := client.request(ctx, "listWorktrees", map[string]any{"projectID": projectID})
	if err != nil {
		return "", err
	}
	var worktrees []struct {
		ID   string `json:"id"`
		Name string `json:"name"`
	}
	json.Unmarshal(wtValue, &worktrees)
	if len(worktrees) > 0 {
		wtNames := make([]string, len(worktrees))
		for i, w := range worktrees {
			wtNames[i] = w.Name
		}
		widx, err := pick("Worktree", wtNames, os.Stdin, os.Stderr)
		if err != nil {
			return "", err
		}
		if _, err := client.request(ctx, "selectWorktree", map[string]any{
			"projectID": projectID, "worktreeID": worktrees[widx].ID,
		}); err != nil {
			return "", err
		}
	}

	wsValue, err := client.request(ctx, "getWorkspace", map[string]any{"projectID": projectID})
	if err != nil {
		return "", err
	}
	var ws struct {
		Root json.RawMessage `json:"root"`
	}
	if err := json.Unmarshal(wsValue, &ws); err != nil {
		return "", err
	}
	panes, err := collectTerminalPanes(ws.Root)
	if err != nil {
		return "", err
	}
	if len(panes) == 0 {
		return "", fmt.Errorf("no terminal sessions in this project")
	}
	titles := make([]string, len(panes))
	for i, p := range panes {
		titles[i] = p.Title
	}
	idx, err := pick("Terminal session", titles, os.Stdin, os.Stderr)
	if err != nil {
		return "", err
	}
	return panes[idx].ID, nil
}

var _ = term.IsTerminal
```

> Note: the trailing `var _ = term.IsTerminal` keeps `golang.org/x/term` imported for a future TTY check; remove it once another `term` call is added. If `go vet` flags the unused import instead, delete the import line — do not leave an unused import.

- [ ] **Step 2: Build**

Run: `cd clients/muxy-remote && go build -o /tmp/muxy-remote . && echo OK`
Expected: `OK` (compiles).

- [ ] **Step 3: Full test + vet**

Run: `cd clients/muxy-remote && go test ./... && go vet ./...`
Expected: PASS.

- [ ] **Step 4: README**

`clients/muxy-remote/README.md`:

```markdown
# muxy-remote

Take over a Mac Muxy terminal pane from an Ubuntu terminal, like `ssh` / `tmux attach`.

## Build

    go build -o muxy-remote ./clients/muxy-remote
    scp muxy-remote you@ubuntu:~/

Single static binary, no runtime deps — works on headless servers.

## Use

On the Mac: **Settings → Mobile → enable**. Then on Ubuntu:

    ./muxy-remote --host <mac-host> [--port 4865]

First run prompts approval on the Mac. Pick a project, then a terminal session; you're attached. Press **Ctrl-]** to detach.

Ports: release `4865`, dev `4866`.

## Reaching the Mac

- **Same LAN:** `--host <mac-lan-ip>`
- **Tailscale:** install on both, `--host <mac-100.x>`
- **SSH tunnel:** `ssh -L 4865:localhost:4865 you@mac` then `--host localhost`

Plaintext `ws://` — trusted networks only; tunnel anything beyond the LAN.
```

- [ ] **Step 5: Commit**

```bash
gofmt -w clients/muxy-remote/main.go
git add clients/muxy-remote/main.go clients/muxy-remote/README.md
git commit -m "feat(muxy-remote): CLI orchestration and README"
```

---

## Task 9: Final build + manual verification

- [ ] **Step 1: Clean build**

Run: `cd clients/muxy-remote && go build -o muxy-remote . && ./muxy-remote --help`
Expected: usage printed; binary exists.

- [ ] **Step 2: Manual attach (user, against live Muxy)**

With Muxy running (Settings → Mobile enabled) on the Mac, from a terminal:

```
./muxy-remote --host localhost --port 4866   # dev build; or 4865 for release, or the LAN/Tailscale host
```

Approve on the Mac → pick project → pick session → confirm output streams and typing works → `Ctrl-]` detaches cleanly (terminal not left in raw mode).

- [ ] **Step 3: Commit any fixes from manual testing**

```bash
git add -A && git commit -m "fix(muxy-remote): address manual-test findings"
```

---

## Self-Review

- **Spec coverage:** protocol (Task 1), workspace walk (Task 2), creds (Task 3), WS client (Task 4), auth/pair (Task 5), picker (Task 6), attach/raw-tty/detach/resize (Task 7), orchestration + README + distribution (Task 8-9). All spec sections covered.
- **Placeholders:** none — every code step is complete; the `term` import note in Task 8 gives an explicit either/or, not a TBD.
- **Type consistency:** `encodeRequest`/`decodeIncoming`/`responsePayload`/`eventPayload`/`dataBody`/`rpcError` (Task 1) reused verbatim in Tasks 4-7; `Client.request(ctx, method, value)`/`sendInput`/`events`/`authenticate` consistent across Tasks 4/5/7/8; `collectTerminalPanes`→`[]Pane{ID,Title}` (Task 2) consumed in Task 8; `pick(prompt, items, in, out)` (Task 6) consumed in Task 8; `runAttach(ctx, client, paneID, fd, in, out)` / `pumpOutput` / `scanForDetach` / `detachByte` (Task 7) consistent.
