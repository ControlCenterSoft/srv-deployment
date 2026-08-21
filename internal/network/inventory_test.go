package network

import "testing"

func TestInventoryIsDeterministicAndNonEmptyOnSupportedHost(t *testing.T) {
	first, err := Inventory()
	if err != nil {
		t.Fatalf("Inventory() error = %v", err)
	}
	second, err := Inventory()
	if err != nil {
		t.Fatalf("Inventory() second error = %v", err)
	}
	if len(first) == 0 {
		t.Fatal("Inventory() returned no interfaces")
	}
	if len(first) != len(second) {
		t.Fatalf("interface count changed between snapshots: %d != %d", len(first), len(second))
	}
	for i, item := range first {
		if item.Name == "" {
			t.Fatalf("interface %d has empty name", i)
		}
		if item.Index <= 0 {
			t.Fatalf("interface %q has invalid index %d", item.Name, item.Index)
		}
		if item.MTU < 0 {
			t.Fatalf("interface %q has invalid MTU %d", item.Name, item.MTU)
		}
		if i > 0 && first[i-1].Index > item.Index {
			t.Fatalf("inventory is not sorted by index: %d before %d", first[i-1].Index, item.Index)
		}
	}
}
