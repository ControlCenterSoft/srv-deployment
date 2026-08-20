package operations

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestLifecyclePersists(t *testing.T) {
	dir := t.TempDir()
	s, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.Start("op-1", "rbac.user.create", "admin", "admin", "viewer"); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Finish("op-1", StatusSucceeded, ""); err != nil {
		t.Fatal(err)
	}
	reopened, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	list := reopened.List(10)
	if len(list) != 1 || list[0].Status != StatusSucceeded || list[0].ID != "op-1" {
		t.Fatalf("unexpected records: %+v", list)
	}
}

func TestRunningOperationBecomesInterruptedAfterRestart(t *testing.T) {
	dir := t.TempDir()
	s, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.Start("op-1", "auth.password.change", "admin", "admin", "admin"); err != nil {
		t.Fatal(err)
	}
	reopened, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	rec := reopened.List(1)[0]
	if rec.Status != StatusInterrupted || rec.ErrorCode != "process_restarted" || rec.FinishedAt == nil {
		t.Fatalf("unexpected interrupted record: %+v", rec)
	}
}

func TestUnsupportedSchemaFailsClosed(t *testing.T) {
	dir := t.TempDir()
	b, _ := json.Marshal(map[string]any{"schema": 99, "records": map[string]any{}})
	if err := os.WriteFile(filepath.Join(dir, "operations.json"), b, 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := Open(dir); err == nil {
		t.Fatal("expected schema error")
	}
}
