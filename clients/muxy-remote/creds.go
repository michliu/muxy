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
