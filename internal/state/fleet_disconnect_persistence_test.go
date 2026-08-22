package state

import (
	"path/filepath"
	"testing"
	"time"
)

func TestDisconnectFleetNodeRetryPersistsRevocationAfterWriteFailure(t *testing.T) {
	dir := t.TempDir()
	store, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}

	node, err := store.CreateFleetNode("srv-01", "10.10.0.11", "", "")
	if err != nil {
		t.Fatal(err)
	}
	_, enrollmentToken, err := store.PrepareFleetEnrollment(node.ID, time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	_, agentCredential, err := store.EnrollFleetNode(node.ID, enrollmentToken, "1.1.9")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := store.RecordFleetHeartbeat(node.ID, agentCredential, FleetHeartbeat{AgentVersion: "1.1.9"}); err != nil {
		t.Fatalf("heartbeat before disconnect: %v", err)
	}

	originalSecretPath := store.secretPath
	store.secretPath = filepath.Join(dir, "missing", "secrets.json")
	_, _, firstErr := store.DisconnectFleetNode(node.ID)
	store.secretPath = originalSecretPath
	if firstErr == nil {
		t.Fatal("disconnect unexpectedly persisted while secret state path was unavailable")
	}

	disconnected, changed, err := store.DisconnectFleetNode(node.ID)
	if err != nil {
		t.Fatalf("idempotent disconnect retry: %v", err)
	}
	if changed {
		t.Fatal("retry should observe the already-revoked in-memory state")
	}
	if disconnected.Status != "pending_enrollment" {
		t.Fatalf("unexpected status after retry: %q", disconnected.Status)
	}

	reopened, err := Open(dir)
	if err != nil {
		t.Fatalf("reopen after successful retry: %v", err)
	}
	if _, err := reopened.RecordFleetHeartbeat(node.ID, agentCredential, FleetHeartbeat{AgentVersion: "1.1.9"}); err == nil {
		t.Fatal("pre-disconnect agent credential became valid again after restart")
	}
}
