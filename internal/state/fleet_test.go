package state

import "testing"

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
