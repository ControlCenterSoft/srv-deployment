package storage

import (
	"errors"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

const (
	defaultSysBlockRoot = "/sys/block"
	sysfsSectorBytes    = uint64(512)
)

// Device is the bounded, read-only representation of a top-level Linux block
// device exposed by Control Center. It intentionally excludes identifiers,
// labels, mount paths and backing-file metadata that may disclose user data.
type Device struct {
	Name              string `json:"name"`
	DevicePath        string `json:"device_path"`
	SizeBytes         uint64 `json:"size_bytes"`
	ReadOnly          bool   `json:"read_only"`
	Removable         bool   `json:"removable"`
	LogicalBlockSize  uint64 `json:"logical_block_size,omitempty"`
	PhysicalBlockSize uint64 `json:"physical_block_size,omitempty"`
}

// Warning reports bounded inventory degradation without exposing host paths or
// raw operating-system errors.
type Warning struct {
	Code   string `json:"code"`
	Device string `json:"device"`
}

type Snapshot struct {
	Devices  []Device  `json:"devices"`
	Warnings []Warning `json:"warnings"`
}

// Inventory returns a deterministic read-only snapshot of top-level Linux
// block devices from sysfs. Per-device hot-unplug or malformed metadata does
// not fail the whole inventory; the affected device is omitted with a bounded
// warning. Failure to read the inventory root is fatal.
func Inventory() (Snapshot, error) {
	return inventoryAt(defaultSysBlockRoot)
}

func inventoryAt(root string) (Snapshot, error) {
	entries, err := os.ReadDir(root)
	if err != nil {
		return Snapshot{}, fmt.Errorf("read block inventory: %w", err)
	}

	devices := make([]Device, 0, len(entries))
	warnings := make([]Warning, 0)
	for _, entry := range entries {
		name := strings.TrimSpace(entry.Name())
		if name == "" {
			continue
		}
		device, err := readDevice(root, name)
		if err != nil {
			code := "device_metadata_unavailable"
			if errors.Is(err, os.ErrNotExist) {
				code = "device_disappeared"
			}
			warnings = append(warnings, Warning{Code: code, Device: name})
			continue
		}
		devices = append(devices, device)
	}

	sort.Slice(devices, func(i, j int) bool { return devices[i].Name < devices[j].Name })
	sort.Slice(warnings, func(i, j int) bool {
		if warnings[i].Device == warnings[j].Device {
			return warnings[i].Code < warnings[j].Code
		}
		return warnings[i].Device < warnings[j].Device
	})
	return Snapshot{Devices: devices, Warnings: warnings}, nil
}

func readDevice(root, name string) (Device, error) {
	base := filepath.Join(root, name)
	sectors, err := readUint(filepath.Join(base, "size"))
	if err != nil {
		return Device{}, err
	}
	if sectors > math.MaxUint64/sysfsSectorBytes {
		return Device{}, fmt.Errorf("block device size overflows bytes")
	}
	readOnly, err := readBool01(filepath.Join(base, "ro"))
	if err != nil {
		return Device{}, err
	}
	removable, err := readBool01(filepath.Join(base, "removable"))
	if err != nil {
		return Device{}, err
	}

	device := Device{
		Name:       name,
		DevicePath: "/dev/" + name,
		SizeBytes:  sectors * sysfsSectorBytes,
		ReadOnly:   readOnly,
		Removable:  removable,
	}
	device.LogicalBlockSize, _ = readUint(filepath.Join(base, "queue", "logical_block_size"))
	device.PhysicalBlockSize, _ = readUint(filepath.Join(base, "queue", "physical_block_size"))
	return device, nil
}

func readUint(path string) (uint64, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return 0, err
	}
	value := strings.TrimSpace(string(raw))
	if value == "" {
		return 0, fmt.Errorf("empty numeric sysfs value")
	}
	parsed, err := strconv.ParseUint(value, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("invalid numeric sysfs value: %w", err)
	}
	return parsed, nil
}

func readBool01(path string) (bool, error) {
	value, err := readUint(path)
	if err != nil {
		return false, err
	}
	switch value {
	case 0:
		return false, nil
	case 1:
		return true, nil
	default:
		return false, fmt.Errorf("invalid boolean sysfs value")
	}
}
