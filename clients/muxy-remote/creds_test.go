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
