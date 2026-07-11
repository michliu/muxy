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
