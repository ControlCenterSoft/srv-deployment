package network

import (
	"net"
	"testing"
)

func TestFlagsOfStableContract(t *testing.T) {
	got := flagsOf(net.FlagUp | net.FlagBroadcast | net.FlagMulticast)
	want := []string{"up", "broadcast", "multicast"}
	if len(got) != len(want) {
		t.Fatalf("flags length=%d want=%d: %#v", len(got), len(want), got)
	}
	for i := range want {
		if got[i] != want[i] { t.Fatalf("flags[%d]=%q want=%q", i, got[i], want[i]) }
	}
}

func TestSystemProviderSnapshotContract(t *testing.T) {
	snapshot, err := (SystemProvider{}).Snapshot()
	if err != nil { t.Fatal(err) }
	if snapshot.Schema != SchemaVersion { t.Fatalf("schema=%d want=%d", snapshot.Schema, SchemaVersion) }
	if snapshot.ObservedAt.IsZero() { t.Fatal("observed_at must be set") }
	if len(snapshot.Interfaces) == 0 { t.Fatal("expected at least loopback interface") }
	seen := map[string]bool{}
	for _, item := range snapshot.Interfaces {
		if item.ID == "" || item.Name == "" { t.Fatalf("interface identity missing: %#v", item) }
		if item.ID != item.Name { t.Fatalf("v1 id must be stable interface name: %#v", item) }
		if item.MTU <= 0 { t.Fatalf("invalid MTU for %s: %d", item.Name, item.MTU) }
		if seen[item.ID] { t.Fatalf("duplicate interface id %q", item.ID) }
		seen[item.ID] = true
		if item.OperationalState != "up" && item.OperationalState != "down" { t.Fatalf("unexpected state %q", item.OperationalState) }
	}
}
