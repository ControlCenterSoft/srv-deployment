//go:build linux

package privileged

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"path/filepath"
	"testing"
	"time"
)

func TestSocketClientRequiresPath(t *testing.T) {
	client := SocketClient{}
	_, err := client.Execute(context.Background(), Request{ID: "op-1", Type: OperationServiceRestart, ActorID: "admin", Args: map[string]string{"service": "control-center.service"}})
	if !errors.Is(err, ErrInvalidRequest) {
		t.Fatalf("expected ErrInvalidRequest, got %v", err)
	}
}

func TestSocketClientSuccess(t *testing.T) {
	path := filepath.Join(t.TempDir(), "worker.sock")
	serveOneClientResponse(t, path, func(req Envelope) ResponseEnvelope {
		return ResponseEnvelope{
			Version: ProtocolVersion,
			Result: Result{ID: req.Request.ID, Type: req.Request.Type, Status: "succeeded", ExitCode: 0},
		}
	})

	client := SocketClient{Path: path, Timeout: time.Second}
	result, err := client.Execute(context.Background(), Request{ID: "op-2", Type: OperationServiceRestart, ActorID: "admin", Args: map[string]string{"service": "control-center.service"}})
	if err != nil {
		t.Fatal(err)
	}
	if result.ID != "op-2" || result.Type != OperationServiceRestart || result.Status != "succeeded" || result.ExitCode != 0 {
		t.Fatalf("unexpected result: %+v", result)
	}
}

func TestSocketClientRejectsResponseProtocolDrift(t *testing.T) {
	path := filepath.Join(t.TempDir(), "worker.sock")
	serveOneClientResponse(t, path, func(req Envelope) ResponseEnvelope {
		return ResponseEnvelope{
			Version: ProtocolVersion + 1,
			Result: Result{ID: req.Request.ID, Type: req.Request.Type, Status: "succeeded", ExitCode: 0},
		}
	})

	client := SocketClient{Path: path, Timeout: time.Second}
	_, err := client.Execute(context.Background(), Request{ID: "op-3", Type: OperationServiceRestart, ActorID: "admin", Args: map[string]string{"service": "control-center.service"}})
	var remote *RemoteError
	if !errors.As(err, &remote) || remote.Code != ErrorCodeProtocol {
		t.Fatalf("expected protocol RemoteError, got %v", err)
	}
}

func TestSocketClientRejectsResponseIdentityMismatch(t *testing.T) {
	path := filepath.Join(t.TempDir(), "worker.sock")
	serveOneClientResponse(t, path, func(req Envelope) ResponseEnvelope {
		return ResponseEnvelope{
			Version: ProtocolVersion,
			Result: Result{ID: req.Request.ID + "-wrong", Type: req.Request.Type, Status: "succeeded", ExitCode: 0},
		}
	})

	client := SocketClient{Path: path, Timeout: time.Second}
	_, err := client.Execute(context.Background(), Request{ID: "op-4", Type: OperationServiceRestart, ActorID: "admin", Args: map[string]string{"service": "control-center.service"}})
	var remote *RemoteError
	if !errors.As(err, &remote) || remote.Code != ErrorCodeProtocol {
		t.Fatalf("expected protocol RemoteError, got %v", err)
	}
}

func TestSocketClientPreservesRemoteFailureCode(t *testing.T) {
	path := filepath.Join(t.TempDir(), "worker.sock")
	serveOneClientResponse(t, path, func(req Envelope) ResponseEnvelope {
		return ResponseEnvelope{
			Version: ProtocolVersion,
			Result: Result{ID: req.Request.ID, Type: req.Request.Type, Status: "failed", ExitCode: -1},
			Error: &Failure{Code: ErrorCodePermissionDenied, Message: "service is not allowlisted"},
		}
	})

	client := SocketClient{Path: path, Timeout: time.Second}
	result, err := client.Execute(context.Background(), Request{ID: "op-5", Type: OperationServiceRestart, ActorID: "admin", Args: map[string]string{"service": "forbidden.service"}})
	var remote *RemoteError
	if !errors.As(err, &remote) || remote.Code != ErrorCodePermissionDenied {
		t.Fatalf("expected permission RemoteError, got %v", err)
	}
	if result.ID != "op-5" || result.Type != OperationServiceRestart || result.Status != "failed" {
		t.Fatalf("unexpected failed result: %+v", result)
	}
}

func serveOneClientResponse(t *testing.T, path string, response func(Envelope) ResponseEnvelope) {
	t.Helper()
	listener, err := net.ListenUnix("unix", &net.UnixAddr{Name: path, Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = listener.Close() })

	done := make(chan struct{})
	go func() {
		defer close(done)
		conn, err := listener.AcceptUnix()
		if err != nil {
			return
		}
		defer conn.Close()
		var request Envelope
		if err := json.NewDecoder(conn).Decode(&request); err != nil {
			return
		}
		_ = json.NewEncoder(conn).Encode(response(request))
	}()

	t.Cleanup(func() {
		_ = listener.Close()
		select {
		case <-done:
		case <-time.After(time.Second):
			t.Error("test socket server did not stop")
		}
	})
}
