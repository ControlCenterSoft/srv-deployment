package httpserver

import (
	"strings"
	"testing"
)

func TestAdminWebStorageInventoryWorkflowContract(t *testing.T) {
	index := readWebAsset(t, "web/index.html")
	storage := readWebAsset(t, "web/storage.js")

	for _, required := range []string{
		`id="storage-devices"`,
		`src="/storage.js"`,
	} {
		if !strings.Contains(index, required) {
			t.Fatalf("storage Admin Web mount is missing %q", required)
		}
	}

	for _, required := range []string{
		`/api/v1/storage/devices`,
		`data.devices`,
		`device.device_path`,
		`device.size_bytes`,
		`device.read_only`,
		`device.removable`,
		`device.logical_block_size`,
		`device.physical_block_size`,
		`data.warnings`,
		`data.management`,
		`management.apply_supported`,
		`management.preview_supported`,
		`management.preflight_supported`,
	} {
		if !strings.Contains(storage, required) {
			t.Fatalf("storage Admin Web workflow is missing %q", required)
		}
	}
}

func TestAdminWebStorageInventoryStatesAndAccessibility(t *testing.T) {
	storage := readWebAsset(t, "web/storage.js")

	for _, required := range []string{
		`Загрузка инвентаря накопителей…`,
		`Блочные устройства не обнаружены.`,
		`Предупреждения инвентаря`,
		`Не удалось загрузить инвентарь накопителей:`,
		`status.role = "status"`,
		`status.setAttribute("aria-live", "polite")`,
		`message.role = "alert"`,
		`storageLoadGeneration += 1`,
		`if (generation !== storageLoadGeneration) return`,
	} {
		if !strings.Contains(storage, required) {
			t.Fatalf("storage loading/error/empty/accessibility contract is missing %q", required)
		}
	}
}

func TestAdminWebStorageInventoryKeepsCoreAuthoritative(t *testing.T) {
	storage := readWebAsset(t, "web/storage.js")

	if strings.Contains(storage, `method:"POST"`) || strings.Contains(storage, `method: "POST"`) {
		t.Fatal("read-only storage inventory UI must not invent a storage mutation")
	}
	if strings.Contains(storage, "innerHTML") {
		t.Fatal("storage API values must be rendered through DOM text, not HTML interpolation")
	}
	for _, forbidden := range []string{"serial_number", "wwn", "filesystem_label", "mount_path", "backing_file"} {
		if strings.Contains(storage, forbidden) {
			t.Fatalf("storage UI must not request or render excluded sensitive metadata %q", forbidden)
		}
	}
	for _, required := range []string{
		`Core capabilities: inventory`,
		`Ограничение Core:`,
		`storageSupportLabel(management.partitions_supported)`,
		`storageSupportLabel(management.filesystems_supported)`,
		`storageSupportLabel(management.mounts_supported)`,
	} {
		if !strings.Contains(storage, required) {
			t.Fatalf("storage UI must surface server-authoritative capability metadata %q", required)
		}
	}
}

func TestAdminWebStorageInventoryIsolatedNavigationLifecycle(t *testing.T) {
	storage := readWebAsset(t, "web/storage.js")

	for _, required := range []string{
		`document.querySelectorAll(".nav-item")`,
		`container.hidden = true`,
		`if (button.dataset.page === "system") loadStorageDevices()`,
	} {
		if !strings.Contains(storage, required) {
			t.Fatalf("storage navigation lifecycle is missing %q", required)
		}
	}
}
