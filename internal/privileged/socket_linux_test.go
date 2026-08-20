//go:build linux

package privileged

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func startOneShotSocketServer(t *testing.T, server *SocketServer) (string, func()) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "worker.sock")
	listener, err := ListenUnix(path, 0600)
	if err != nil {
		t.Fatal(err)
	}
	done := make(chan struct{})
	go func() {
		defer close(done)
		conn, err := listener.AcceptUnix()
		if err != nil {
			return
		}
		defer conn.Close()
		_ = server.HandleConn(context.Background(), conn)
	}()
	return path, func() {
		_ = listener.Close()
		<-done
	}
}

func TestSocketBoundaryExecutesAuthorizedTypedRequest(t *testing.T) {
	runner := &fakeRunner{result: CommandResult{ExitCode: 0, Output: "restarted"}}
	server, err := NewSocketServer(newTestEngine(t, runner), []uint32{uint32(os.Getuid())})
	if err != nil {
		t.Fatal(err)
	}
	path, stop := startOneShotSocketServer(t, server)
	defer stop()

	client := SocketClient{Path: path, Timeout: time.Second}
	result, err := client.Execute(context.Background(), Request{
		ID:      "op-socket-1",
		Type:    OperationServiceRestart,
		ActorID: "actor-1",
		Args:    map[string]string{"service": "nginx.service"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if result.Status != "succeeded" || result.Output != "restarted" {
		t.Fatalf("unexpected result: %+v", result)
	}
	if runner.calls != 1 {
		t.Fatalf("runner calls=%d", runner.calls)
	}
}

func TestSocketBoundaryAuditsSuccessfulExecutionCorrelation(t *testing.T) {
	runner := &fakeRunner{result: CommandResult{ExitCode: 0, Output: "sensitive output is not copied to audit"}}
	server, err := NewSocketServer(newTestEngine(t, runner), []uint32{uint32(os.Getuid())})
	if err != nil {
		t.Fatal(err)
	}
	var events []AuditEvent
	server.Audit = AuditSinkFunc(func(event AuditEvent) { events = append(events, event) })
	path, stop := startOneShotSocketServer(t, server)
	defer stop()

	client := SocketClient{Path: path, Timeout: time.Second}
	_, err = client.Execute(context.Background(), Request{
		ID:      "op-audit-success",
		Type:    OperationServiceRestart,
		ActorID: "actor-admin-42",
		Args:    map[string]string{"service": "nginx.service"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 1 {
		t.Fatalf("audit events=%d", len(events))
	}
	event := events[0]
	if event.OperationID != "op-audit-success" || event.ActorID != "actor-admin-42" {
		t.Fatalf("unexpected correlation: %+v", event)
	}
	if event.Type != OperationServiceRestart || event.Status != "succeeded" || event.ExitCode != 0 || event.ErrorCode != "" {
		t.Fatalf("unexpected audit event: %+v", event)
	}
	if event.StartedAt.IsZero() || event.FinishedAt.Before(event.StartedAt) || event.DurationMS < 0 {
		t.Fatalf("invalid audit timing: %+v", event)
	}
}

func TestSocketBoundaryAuditsRejectedTypedExecution(t *testing.T) {
	runner := &fakeRunner{}
	server, err := NewSocketServer(newTestEngine(t, runner), []uint32{uint32(os.Getuid())})
	if err != nil {
		t.Fatal(err)
	}
	var events []AuditEvent
	server.Audit = AuditSinkFunc(func(event AuditEvent) { events = append(events, event) })
	path, stop := startOneShotSocketServer(t, server)
	defer stop()

	client := SocketClient{Path: path, Timeout: time.Second}
	_, err = client.Execute(context.Background(), Request{
		ID:      "op-audit-denied",
		Type:    OperationServiceRestart,
		ActorID: "actor-viewer",
		Args:    map[string]string{"service": "ssh.service"},
	})
	var remoteErr *RemoteError
	if !errors.As(err, &remoteErr) || remoteErr.Code != ErrorCodePermissionDenied {
		t.Fatalf("error=%v", err)
	}
	if runner.calls != 0 {
		t.Fatalf("runner called %d times", runner.calls)
	}
	if len(events) != 1 {
		t.Fatalf("audit events=%d", len(events))
	}
	event := events[0]
	if event.OperationID != "op-audit-denied" || event.ActorID != "actor-viewer" || event.ErrorCode != ErrorCodePermissionDenied || event.Status != "failed" {
		t.Fatalf("unexpected audit event: %+v", event)
	}
}

func TestSocketBoundaryRejectsUnauthorizedPeerBeforeExecution(t *testing.T) {
	runner := &fakeRunner{}
	server, err := NewSocketServer(newTestEngine(t, runner), []uint32{uint32(os.Getuid() + 1)})
	if err != nil {
		t.Fatal(err)
	}
	path, stop := startOneShotSocketServer(t, server)
	defer stop()

	client := SocketClient{Path: path, Timeout: time.Second}
	_, err = client.Execute(context.Background(), Request{
		ID:      "op-denied",
		Type:    OperationServiceRestart,
		ActorID: "actor-1",
		Args:    map[string]string{"service": "nginx.service"},
	})
	var remoteErr *RemoteError
	if !errors.As(err, &remoteErr) || remoteErr.Code != ErrorCodePermissionDenied {
		t.Fatalf("error=%v", err)
	}
	if runner.calls != 0 {
		t.Fatalf("runner called %d times", runner.calls)
	}
}

func TestSocketBoundaryRejectsUnknownEnvelopeFields(t *testing.T) {
	runner := &fakeRunner{}
	server, err := NewSocketServer(newTestEngine(t, runner), []uint32{uint32(os.Getuid())})
	if err != nil {
		t.Fatal(err)
	}
	path, stop := startOneShotSocketServer(t, server)
	defer stop()

	conn, err := net.DialUnix("unix", nil, &net.UnixAddr{Name: path, Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	_, _ = conn.Write([]byte(`{"version":1,"request":{"id":"op-1","type":"service.restart","actor_id":"actor","args":{"service":"nginx.service"}},"unexpected":true}`))
	_ = conn.CloseWrite()
	defer conn.Close()

	var response ResponseEnvelope
	if err := json.NewDecoder(conn).Decode(&response); err != nil {
		t.Fatal(err)
	}
	if response.Error == nil || response.Error.Code != ErrorCodeProtocol {
		t.Fatalf("response=%+v", response)
	}
	if runner.calls != 0 {
		t.Fatalf("runner called %d times", runner.calls)
	}
}

func TestSocketBoundaryEnforcesRequestSizeLimit(t *testing.T) {
	runner := &fakeRunner{}
	server, err := NewSocketServer(newTestEngine(t, runner), []uint32{uint32(os.Getuid())})
	if err != nil {
		t.Fatal(err)
	}
	server.MaxRequestBytes = 128
	path, stop := startOneShotSocketServer(t, server)
	defer stop()

	conn, err := net.DialUnix("unix", nil, &net.UnixAddr{Name: path, Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	_, _ = conn.Write([]byte(strings.Repeat("x", 129)))
	_ = conn.CloseWrite()
	defer conn.Close()

	var response ResponseEnvelope
	if err := json.NewDecoder(conn).Decode(&response); err != nil {
		t.Fatal(err)
	}
	if response.Error == nil || response.Error.Code != ErrorCodeProtocol {
		t.Fatalf("response=%+v", response)
	}
	if runner.calls != 0 {
		t.Fatalf("runner called %d times", runner.calls)
	}
}

func TestListenUnixRejectsOverPermissiveMode(t *testing.T) {
	_, err := ListenUnix(filepath.Join(t.TempDir(), "worker.sock"), 0666)
	if !errors.Is(err, ErrInvalidRequest) {
		t.Fatalf("error=%v", err)
	}
}
