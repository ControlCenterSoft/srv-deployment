//go:build linux

package privileged

import (
	"bufio"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestJSONLAuditSinkWritesDurableNormalizedEvent(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "privileged-audit.jsonl")
	sink, err := NewJSONLAuditSink(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := sink.Ready(); err != nil {
		t.Fatal(err)
	}
	event := AuditEvent{
		OperationID: "op-1",
		ActorID:     "actor-1",
		Type:        OperationServiceRestart,
		Status:      "succeeded",
		ExitCode:    0,
		StartedAt:   time.Unix(10, 0).UTC(),
		FinishedAt:  time.Unix(11, 0).UTC(),
		DurationMS:  1000,
	}
	if err := sink.RecordDurable(event); err != nil {
		t.Fatal(err)
	}

	file, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	var got AuditEvent
	if err := json.NewDecoder(bufio.NewReader(file)).Decode(&got); err != nil {
		t.Fatal(err)
	}
	if got.OperationID != event.OperationID || got.ActorID != event.ActorID || got.Type != event.Type || got.Status != event.Status {
		t.Fatalf("unexpected event: %+v", got)
	}
	info, err := file.Stat()
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0600 {
		t.Fatalf("audit mode=%#o", info.Mode().Perm())
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
	sink, err := NewJSONLAuditSink(link)
	if err != nil {
		t.Fatal(err)
	}
	if err := sink.Ready(); err == nil {
		t.Fatal("expected symlink rejection")
	}
	payload, err := os.ReadFile(target)
	if err != nil {
		t.Fatal(err)
	}
	if string(payload) != "do-not-touch" {
		t.Fatalf("target modified: %q", payload)
	}
}

func TestJSONLAuditSinkRejectsWritableParent(t *testing.T) {
	dir := t.TempDir()
	if err := os.Chmod(dir, 0770); err != nil {
		t.Fatal(err)
	}
	if _, err := NewJSONLAuditSink(filepath.Join(dir, "audit.jsonl")); err == nil {
		t.Fatal("expected writable parent rejection")
	}
}
