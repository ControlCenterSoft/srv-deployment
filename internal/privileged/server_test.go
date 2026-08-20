package privileged

import (
	"context"
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestServerRejectsUnknownJSONField(t *testing.T) {
	dir := t.TempDir()
	socket := filepath.Join(dir, "worker.sock")
	runner, _ := NewRunner([]string{"control-center.service"}, []string{ActionSystemdStatus})
	fake := &fakeExec{}
	runner.Exec = fake
	server := &Server{SocketPath: socket, AllowedUID: os.Getuid(), Runner: runner}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	errCh := make(chan error, 1)
	go func() { errCh <- server.Serve(ctx) }()
	waitForSocket(t, socket)
	conn, err := net.Dial("unix", socket)
	if err != nil {
		t.Fatal(err)
	}
	_, _ = conn.Write([]byte(`{"schema":1,"operation_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","action":"systemd.unit.status","target":"control-center.service","command":"id"}` + "\n"))
	var resp Response
	if err := json.NewDecoder(conn).Decode(&resp); err != nil {
		t.Fatal(err)
	}
	_ = conn.Close()
	if resp.Status != "rejected" || resp.Error == nil || resp.Error.Code != "invalid_json" {
		t.Fatalf("response=%+v", resp)
	}
	if fake.path != "" {
		t.Fatal("executor should not be called")
	}
	cancel()
	select {
	case err := <-errCh:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("server did not stop")
	}
}

func TestClientChecksOperationIdentity(t *testing.T) {
	dir := t.TempDir()
	socket := filepath.Join(dir, "fake.sock")
	ln, err := net.Listen("unix", socket)
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	go func() {
		conn, _ := ln.Accept()
		if conn == nil {
			return
		}
		defer conn.Close()
		var req Request
		_ = json.NewDecoder(conn).Decode(&req)
		_ = json.NewEncoder(conn).Encode(Response{Schema: SchemaVersion, OperationID: strings.Repeat("b", 32), Status: "succeeded"})
	}()
	client := Client{SocketPath: socket, Timeout: time.Second}
	_, err = client.Do(context.Background(), validRequest(ActionSystemdStatus, "control-center.service"))
	if err == nil {
		t.Fatal("expected identity mismatch")
	}
}

func TestRemoveStaleSocketRefusesRegularFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "worker.sock")
	if err := os.WriteFile(path, []byte("do not delete"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := removeStaleSocket(path); err == nil {
		t.Fatal("expected refusal")
	}
	body, _ := os.ReadFile(path)
	if string(body) != "do not delete" {
		t.Fatalf("file changed: %q", body)
	}
}

func waitForSocket(t *testing.T, path string) {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		info, err := os.Stat(path)
		if err == nil && info.Mode()&os.ModeSocket != 0 {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatalf("socket not ready: %s", path)
}

func TestServerRejectsUnexpectedPeerUID(t *testing.T) {
	dir := t.TempDir()
	socket := filepath.Join(dir, "worker.sock")
	runner, err := NewRunner([]string{"control-center.service"}, []string{ActionSystemdStatus})
	if err != nil {
		t.Fatal(err)
	}
	fake := &fakeExec{}
	runner.Exec = fake
	server := &Server{SocketPath: socket, AllowedUID: os.Getuid() + 1, Runner: runner}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	errCh := make(chan error, 1)
	go func() { errCh <- server.Serve(ctx) }()
	waitForSocket(t, socket)
	conn, err := net.Dial("unix", socket)
	if err != nil {
		t.Fatal(err)
	}
	_, _ = conn.Write([]byte(`{"schema":1,"operation_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","action":"systemd.unit.status","target":"control-center.service"}` + "\n"))
	_ = conn.SetReadDeadline(time.Now().Add(250 * time.Millisecond))
	var resp Response
	if err := json.NewDecoder(conn).Decode(&resp); err == nil {
		t.Fatalf("unexpected response: %+v", resp)
	}
	_ = conn.Close()
	if fake.path != "" {
		t.Fatal("executor should not be called")
	}
	cancel()
	select {
	case err := <-errCh:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("server did not stop")
	}
}
