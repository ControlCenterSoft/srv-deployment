//go:build linux

package privileged

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestJSONLAuditSinkPersistsStartedAndTerminalEvents(t *testing.T) {
	path := filepath.Join(t.TempDir(), "privileged-audit.jsonl")
	sink, err := NewJSONLAuditSink(path)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now().UTC().Truncate(time.Millisecond)
	started := AuditEvent{OperationID: "op-1", ActorID: "admin-1", Type: OperationServiceRestart, Status: "started", ExitCode: -1, StartedAt: now, FinishedAt: now}
	finished := started
	finished.Status = "succeeded"
	finished.ExitCode = 0
	finished.FinishedAt = now.Add(time.Millisecond)
	finished.DurationMS = 1
	if err := sink.Begin(started); err != nil {
		t.Fatal(err)
	}
	if err := sink.Record(finished); err != nil {
		t.Fatal(err)
	}
	if err := sink.Close(); err != nil {
		t.Fatal(err)
	}

	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0600 {
		t.Fatalf("audit mode=%#o", info.Mode().Perm())
	}
	file, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	var events []AuditEvent
	for scanner.Scan() {
		var event AuditEvent
		if err := json.Unmarshal(scanner.Bytes(), &event); err != nil {
			t.Fatal(err)
		}
		events = append(events, event)
	}
	if err := scanner.Err(); err != nil {
		t.Fatal(err)
	}
	if len(events) != 2 || events[0].Status != "started" || events[1].Status != "succeeded" {
		t.Fatalf("unexpected events: %+v", events)
	}
}

func TestJSONLAuditSinkRejectsSymlink(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "target")
	if err := os.WriteFile(target, []byte("do-not-touch"), 0600); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(dir, "audit.jsonl")
	if err := os.Symlink(target, link); err != nil {
		t.Fatal(err)
	}
	if _, err := NewJSONLAuditSink(link); err == nil {
		t.Fatal("expected O_NOFOLLOW rejection")
	}
}

type failingBeginAuditSink struct{}

func (failingBeginAuditSink) Begin(AuditEvent) error  { return errors.New("disk unavailable") }
func (failingBeginAuditSink) Record(AuditEvent) error { return nil }

func TestSocketBoundaryFailsClosedWhenDurableAuditCannotStart(t *testing.T) {
	runner := &fakeRunner{result: CommandResult{ExitCode: 0}}
	server, err := NewSocketServer(newTestEngine(t, runner), []uint32{uint32(os.Getuid())})
	if err != nil {
		t.Fatal(err)
	}
	server.Audit = failingBeginAuditSink{}
	path, stop := startOneShotSocketServer(t, server)
	defer stop()

	client := SocketClient{Path: path, Timeout: time.Second}
	_, err = client.Execute(context.Background(), Request{
		ID: "op-audit-fail",
		Type: OperationServiceRestart,
		ActorID: "actor-admin",
		Args: map[string]string{"service": "nginx.service"},
	})
	var remoteErr *RemoteError
	if !errors.As(err, &remoteErr) || remoteErr.Code != ErrorCodeAuditUnavailable {
		t.Fatalf("error=%v", err)
	}
	if runner.calls != 0 {
		t.Fatalf("runner called %d times despite audit failure", runner.calls)
	}
}
