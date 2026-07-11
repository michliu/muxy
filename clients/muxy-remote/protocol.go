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
