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
