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
		time.Sleep(100 * time.Millisecond)
		ev := `{"type":"event","payload":{"event":"terminalOutput","data":{"type":"terminalOutput","value":{"paneID":"x","bytes":"aGk="}}}}`
		c.Write(ctx, websocket.MessageText, []byte(ev))
		time.Sleep(200 * time.Millisecond)
	})
	ctx := context.Background()
	client, _ := dial(ctx, url)
	defer client.close()

	got := make(chan eventPayload, 1)
	client.setEventSink(func(ev eventPayload) {
		select {
		case got <- ev:
		default:
		}
	})

	select {
	case ev := <-got:
		if ev.Event != "terminalOutput" {
			t.Errorf("event = %s", ev.Event)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("no event received")
	}
}
