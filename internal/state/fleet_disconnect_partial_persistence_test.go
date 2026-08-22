package state

import (
	"path/filepath"
	"testing"
	"time"
)

// Covers the second persistLocked failure boundary: secrets.json is written,
// state.json fails, then the same-process idempotent retry must repair the
// revision pair and keep the revoked credential invalid after restart.
func TestDisconnectFleetNodeRetryRepairsStateWriteFailure(t *testing.T) {
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

	originalStatePath := store.statePath
	store.statePath = filepath.Join(dir, "missing", "state.json")
	_, _, firstErr := store.DisconnectFleetNode(node.ID)
	store.statePath = originalStatePath
	if firstErr == nil {
		t.Fatal("disconnect unexpectedly persisted while state path was unavailable")
	}

	disconnected, changed, err := store.DisconnectFleetNode(node.ID)
	if err != nil {
		t.Fatalf("idempotent disconnect retry after partial persist: %v", err)
	}
	if changed {
		t.Fatal("retry should observe the already-revoked in-memory state")
	}
	if disconnected.Status != "pending_enrollment" {
		t.Fatalf("unexpected status after retry: %q", disconnected.Status)
	}

	reopened, err := Open(dir)
	if err != nil {
		t.Fatalf("reopen after retry repaired persistence pair: %v", err)
	}
	if _, err := reopened.RecordFleetHeartbeat(node.ID, agentCredential, FleetHeartbeat{AgentVersion: "1.1.9"}); err == nil {
		t.Fatal("pre-disconnect agent credential became valid again after partial persist + retry + restart")
	}
}
