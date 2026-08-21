package state

import (
	"testing"
	"time"
)

func TestFleetNodePersistenceAndValidation(t *testing.T) {
	dir := t.TempDir()
	store, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	node, err := store.CreateFleetNode("srv-01", "10.10.0.11", "office", "production")
	if err != nil {
		t.Fatal(err)
	}
	if node.ID != "srv-01" || node.Status != "pending_enrollment" {
		t.Fatalf("unexpected node: %+v", node)
	}
	if _, err := store.CreateFleetNode("srv-02", "10.10.0.11", "office", "production"); err == nil {
		t.Fatal("expected duplicate address rejection")
	}
	if _, err := store.CreateFleetNode("bad name", "10.10.0.12", "", ""); err == nil {
		t.Fatal("expected invalid name rejection")
	}

	reopened, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	nodes := reopened.ListFleetNodes()
	if len(nodes) != 1 || nodes[0].Name != "srv-01" || nodes[0].Address != "10.10.0.11" {
		t.Fatalf("unexpected persisted nodes: %+v", nodes)
	}
}

func TestFleetEnrollmentCredentialIsOneTimeAndPersistent(t *testing.T) {
	dir := t.TempDir()
	store, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := store.CreateFleetNode("srv-01", "10.10.0.11", "office", "production"); err != nil {
		t.Fatal(err)
	}
	node, token, err := store.PrepareFleetEnrollment("srv-01", 15*time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	if token == "" || node.Status != "enrollment_ready" || node.EnrollmentExpiresAt == nil {
		t.Fatalf("unexpected enrollment preparation: node=%+v token=%q", node, token)
	}
	if node.EnrollmentTokenHash != "" {
		t.Fatal("public node must never expose enrollment token hash")
	}

	reopened, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := reopened.EnrollFleetNode("srv-01", "wrong-token", "1.1.8"); err == nil {
		t.Fatal("expected invalid token rejection")
	}
	enrolled, err := reopened.EnrollFleetNode("srv-01", token, "1.1.8")
	if err != nil {
		t.Fatal(err)
	}
	if enrolled.Status != "enrolled" || enrolled.AgentVersion != "1.1.8" || enrolled.EnrolledAt == nil || enrolled.LastSeenAt == nil {
		t.Fatalf("unexpected enrolled node: %+v", enrolled)
	}
	if _, err := reopened.EnrollFleetNode("srv-01", token, "1.1.8"); err == nil {
		t.Fatal("expected one-time token replay rejection")
	}
}
