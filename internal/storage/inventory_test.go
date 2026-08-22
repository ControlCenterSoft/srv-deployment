package storage

import (
	"os"
	"path/filepath"
	"testing"
)

func TestInventoryAtReturnsDeterministicSafeBlockMetadata(t *testing.T) {
	root := t.TempDir()
	writeDeviceFixture(t, root, "vdb", "4096", "1", "1", "512", "4096")
	writeDeviceFixture(t, root, "vda", "2048", "0", "0", "512", "512")

	snapshot, err := inventoryAt(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(snapshot.Warnings) != 0 {
		t.Fatalf("unexpected warnings: %+v", snapshot.Warnings)
	}
	if len(snapshot.Devices) != 2 {
		t.Fatalf("device count=%d", len(snapshot.Devices))
	}
	if snapshot.Devices[0].Name != "vda" || snapshot.Devices[1].Name != "vdb" {
		t.Fatalf("unexpected order: %+v", snapshot.Devices)
	}
	first := snapshot.Devices[0]
	if first.DevicePath != "/dev/vda" || first.SizeBytes != 2048*512 || first.ReadOnly || first.Removable {
		t.Fatalf("unexpected vda metadata: %+v", first)
	}
	second := snapshot.Devices[1]
	if !second.ReadOnly || !second.Removable || second.LogicalBlockSize != 512 || second.PhysicalBlockSize != 4096 {
		t.Fatalf("unexpected vdb metadata: %+v", second)
	}
}

func TestInventoryAtOmitsMalformedOrOverflowingDevicesWithBoundedWarnings(t *testing.T) {
	root := t.TempDir()
	writeDeviceFixture(t, root, "good", "1", "0", "0", "", "")
	writeDeviceFixture(t, root, "bad", "not-a-number", "0", "0", "", "")
	writeDeviceFixture(t, root, "huge", maxUintString(), "0", "0", "", "")

	snapshot, err := inventoryAt(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(snapshot.Devices) != 1 || snapshot.Devices[0].Name != "good" {
		t.Fatalf("devices=%+v", snapshot.Devices)
	}
	if len(snapshot.Warnings) != 2 {
		t.Fatalf("warnings=%+v", snapshot.Warnings)
	}
	for _, warning := range snapshot.Warnings {
		if warning.Code != "device_metadata_unavailable" {
			t.Fatalf("unexpected warning=%+v", warning)
		}
		if warning.Device != "bad" && warning.Device != "huge" {
			t.Fatalf("warning leaked unexpected data: %+v", warning)
		}
	}
}

func TestInventoryAtFailsWhenInventoryRootIsUnavailable(t *testing.T) {
	_, err := inventoryAt(filepath.Join(t.TempDir(), "missing"))
	if err == nil {
		t.Fatal("expected inventory root error")
	}
}

func writeDeviceFixture(t *testing.T, root, name, size, ro, removable, logical, physical string) {
	t.Helper()
	base := filepath.Join(root, name)
	if err := os.MkdirAll(filepath.Join(base, "queue"), 0o755); err != nil {
		t.Fatal(err)
	}
	for path, value := range map[string]string{
		"size":      size,
		"ro":        ro,
		"removable": removable,
	} {
		if err := os.WriteFile(filepath.Join(base, path), []byte(value+"\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if logical != "" {
		if err := os.WriteFile(filepath.Join(base, "queue", "logical_block_size"), []byte(logical+"\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if physical != "" {
		if err := os.WriteFile(filepath.Join(base, "queue", "physical_block_size"), []byte(physical+"\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

func maxUintString() string {
	return "18446744073709551615"
}
