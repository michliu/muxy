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
	defer func() {
		c.mu.Lock()
		delete(c.pending, id)
		c.mu.Unlock()
	}()

	if err := c.conn.Write(ctx, websocket.MessageText, frame); err != nil {
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
