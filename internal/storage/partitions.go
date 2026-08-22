package storage

import (
	"errors"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// Partition is the bounded, read-only representation of a Linux block-device
// partition discovered through sysfs. It intentionally excludes filesystem
// identifiers, labels, mount paths and other metadata that may disclose user
// data.
type Partition struct {
	Name            string `json:"name"`
	DevicePath      string `json:"device_path"`
	Parent          string `json:"parent"`
	PartitionNumber uint64 `json:"partition_number"`
	StartBytes      uint64 `json:"start_bytes"`
	SizeBytes       uint64 `json:"size_bytes"`
}

// PartitionWarning reports bounded partition-inventory degradation without
// exposing host paths or raw operating-system errors.
type PartitionWarning struct {
	Code      string `json:"code"`
	Device    string `json:"device"`
	Partition string `json:"partition,omitempty"`
}

type PartitionSnapshot struct {
	Partitions []Partition        `json:"partitions"`
	Warnings   []PartitionWarning `json:"warnings"`
}

// Partitions returns a deterministic, read-only snapshot of partitions below
// top-level Linux block devices. Missing partition markers are treated as
// ordinary non-partition sysfs entries. Hot-unplug or malformed metadata is
// degraded to bounded warnings; failure to read the inventory root is fatal.
func Partitions() (PartitionSnapshot, error) {
	return partitionsAt(defaultSysBlockRoot)
}

func partitionsAt(root string) (PartitionSnapshot, error) {
	parents, err := os.ReadDir(root)
	if err != nil {
		return PartitionSnapshot{}, fmt.Errorf("read block inventory: %w", err)
	}

	partitions := make([]Partition, 0)
	warnings := make([]PartitionWarning, 0)
	for _, parentEntry := range parents {
		parent := strings.TrimSpace(parentEntry.Name())
		if parent == "" {
			continue
		}

		children, err := os.ReadDir(filepath.Join(root, parent))
		if err != nil {
			code := "partition_inventory_unavailable"
			if errors.Is(err, os.ErrNotExist) {
				code = "device_disappeared"
			}
			warnings = append(warnings, PartitionWarning{Code: code, Device: parent})
			continue
		}

		for _, child := range children {
			name := strings.TrimSpace(child.Name())
			if name == "" {
				continue
			}

			partitionNumber, err := readUint(filepath.Join(root, parent, name, "partition"))
			if errors.Is(err, os.ErrNotExist) {
				continue
			}
			if err != nil || partitionNumber == 0 {
				warnings = append(warnings, PartitionWarning{
					Code:      "partition_metadata_unavailable",
					Device:    parent,
					Partition: name,
				})
				continue
			}

			partition, err := readPartition(root, parent, name, partitionNumber)
			if err != nil {
				code := "partition_metadata_unavailable"
				if errors.Is(err, os.ErrNotExist) {
					code = "partition_disappeared"
				}
				warnings = append(warnings, PartitionWarning{
					Code:      code,
					Device:    parent,
					Partition: name,
				})
				continue
			}
			partitions = append(partitions, partition)
		}
	}

	sort.Slice(partitions, func(i, j int) bool {
		if partitions[i].Parent != partitions[j].Parent {
			return partitions[i].Parent < partitions[j].Parent
		}
		if partitions[i].PartitionNumber != partitions[j].PartitionNumber {
			return partitions[i].PartitionNumber < partitions[j].PartitionNumber
		}
		return partitions[i].Name < partitions[j].Name
	})
	sort.Slice(warnings, func(i, j int) bool {
		if warnings[i].Device != warnings[j].Device {
			return warnings[i].Device < warnings[j].Device
		}
		if warnings[i].Partition != warnings[j].Partition {
			return warnings[i].Partition < warnings[j].Partition
		}
		return warnings[i].Code < warnings[j].Code
	})

	return PartitionSnapshot{Partitions: partitions, Warnings: warnings}, nil
}

func readPartition(root, parent, name string, partitionNumber uint64) (Partition, error) {
	base := filepath.Join(root, parent, name)
	startSectors, err := readUint(filepath.Join(base, "start"))
	if err != nil {
		return Partition{}, err
	}
	sizeSectors, err := readUint(filepath.Join(base, "size"))
	if err != nil {
		return Partition{}, err
	}
	if startSectors > math.MaxUint64/sysfsSectorBytes || sizeSectors > math.MaxUint64/sysfsSectorBytes {
		return Partition{}, fmt.Errorf("partition geometry overflows bytes")
	}

	return Partition{
		Name:            name,
		DevicePath:      "/dev/" + name,
		Parent:          parent,
		PartitionNumber: partitionNumber,
		StartBytes:      startSectors * sysfsSectorBytes,
		SizeBytes:       sizeSectors * sysfsSectorBytes,
	}, nil
}
