//go:build linux

package privileged

import (
	"context"
	"errors"
	"os"
	"testing"
	"time"
)

type failingDurableAudit struct {
	readyErr  error
	recordErr error
	records   int
}

func (f *failingDurableAudit) Ready() error { return f.readyErr }
func (f *failingDurableAudit) RecordDurable(AuditEvent) error {
	f.records++
	return f.recordErr
}

func TestSocketBoundaryFailsClosedBeforeExecutionWhenDurableAuditUnavailable(t *testing.T) {
	runner := &fakeRunner{}
	server, err := NewSocketServer(newTestEngine(t, runner), []uint32{uint32(os.Getuid())})
	if err != nil {
		t.Fatal(err)
	}
	server.DurableAudit = &failingDurableAudit{readyErr: errors.New("audit down")}
	path, stop := startOneShotSocketServer(t, server)
	defer stop()

	client := SocketClient{Path: path, Timeout: time.Second}
	_, err = client.Execute(context.Background(), Request{
		ID:      "op-audit-preflight",
		Type:    OperationServiceRestart,
		ActorID: "actor-admin",
		Args:    map[string]string{"service": "nginx.service"},
	})
	var remoteErr *RemoteError
	if !errors.As(err, &remoteErr) || remoteErr.Code != ErrorCodeAuditUnavailable {
		t.Fatalf("error=%v", err)
	}
	if runner.calls != 0 {
		t.Fatalf("runner called %d times", runner.calls)
	}
}

func TestSocketBoundaryReturnsAuditFailureWhenDurableRecordFails(t *testing.T) {
	runner := &fakeRunner{result: CommandResult{ExitCode: 0}}
	server, err := NewSocketServer(newTestEngine(t, runner), []uint32{uint32(os.Getuid())})
	if err != nil {
		t.Fatal(err)
	}
	sink := &failingDurableAudit{recordErr: errors.New("sync failed")}
	server.DurableAudit = sink
	path, stop := startOneShotSocketServer(t, server)
	defer stop()

	client := SocketClient{Path: path, Timeout: time.Second}
	_, err = client.Execute(context.Background(), Request{
		ID:      "op-audit-postwrite",
		Type:    OperationServiceRestart,
		ActorID: "actor-admin",
		Args:    map[string]string{"service": "nginx.service"},
	})
	var remoteErr *RemoteError
	if !errors.As(err, &remoteErr) || remoteErr.Code != ErrorCodeAuditUnavailable {
		t.Fatalf("error=%v", err)
	}
	if runner.calls != 1 || sink.records != 1 {
		t.Fatalf("runner=%d records=%d", runner.calls, sink.records)
	}
}
