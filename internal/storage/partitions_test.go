package storage

import (
	"os"
	"path/filepath"
	"testing"
)

func TestPartitionsAtReturnsDeterministicSafePartitionMetadata(t *testing.T) {
	root := t.TempDir()
	writePartitionFixture(t, root, "nvme0n1", "nvme0n1p2", "2", "4096", "8192")
	writePartitionFixture(t, root, "nvme0n1", "nvme0n1p1", "1", "2048", "1024")
	writePartitionFixture(t, root, "sda", "sda1", "1", "8", "16")
	if err := os.MkdirAll(filepath.Join(root, "nvme0n1", "queue"), 0o755); err != nil {
		t.Fatal(err)
	}

	snapshot, err := partitionsAt(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(snapshot.Warnings) != 0 {
		t.Fatalf("unexpected warnings: %+v", snapshot.Warnings)
	}
	if len(snapshot.Partitions) != 3 {
		t.Fatalf("partition count=%d", len(snapshot.Partitions))
	}

	first := snapshot.Partitions[0]
	if first.Name != "nvme0n1p1" || first.Parent != "nvme0n1" || first.DevicePath != "/dev/nvme0n1p1" || first.PartitionNumber != 1 || first.StartBytes != 2048*512 || first.SizeBytes != 1024*512 {
		t.Fatalf("unexpected first partition: %+v", first)
	}
	second := snapshot.Partitions[1]
	if second.Name != "nvme0n1p2" || second.PartitionNumber != 2 {
		t.Fatalf("unexpected second partition: %+v", second)
	}
	third := snapshot.Partitions[2]
	if third.Name != "sda1" || third.Parent != "sda" || third.PartitionNumber != 1 {
		t.Fatalf("unexpected third partition: %+v", third)
	}
}

func TestPartitionsAtOmitsMalformedOrOverflowingPartitionsWithBoundedWarnings(t *testing.T) {
	root := t.TempDir()
	writePartitionFixture(t, root, "sda", "good", "1", "8", "16")
	writePartitionFixture(t, root, "sda", "bad-number", "invalid", "8", "16")
	writePartitionFixture(t, root, "sda", "huge", "2", "18446744073709551615", "16")
	if err := os.MkdirAll(filepath.Join(root, "sda", "holders"), 0o755); err != nil {
		t.Fatal(err)
	}

	snapshot, err := partitionsAt(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(snapshot.Partitions) != 1 || snapshot.Partitions[0].Name != "good" {
		t.Fatalf("partitions=%+v", snapshot.Partitions)
	}
	if len(snapshot.Warnings) != 2 {
		t.Fatalf("warnings=%+v", snapshot.Warnings)
	}
	for _, warning := range snapshot.Warnings {
		if warning.Code != "partition_metadata_unavailable" {
			t.Fatalf("unexpected warning=%+v", warning)
		}
		if warning.Device != "sda" || (warning.Partition != "bad-number" && warning.Partition != "huge") {
			t.Fatalf("warning leaked unexpected data: %+v", warning)
		}
	}
}

func TestPartitionsAtFailsWhenInventoryRootIsUnavailable(t *testing.T) {
	_, err := partitionsAt(filepath.Join(t.TempDir(), "missing"))
	if err == nil {
		t.Fatal("expected inventory root error")
	}
}

func writePartitionFixture(t *testing.T, root, parent, name, number, start, size string) {
	t.Helper()
	base := filepath.Join(root, parent, name)
	if err := os.MkdirAll(base, 0o755); err != nil {
		t.Fatal(err)
	}
	for path, value := range map[string]string{
		"partition": number,
		"start":     start,
		"size":      size,
	} {
		if err := os.WriteFile(filepath.Join(base, path), []byte(value+"\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}
