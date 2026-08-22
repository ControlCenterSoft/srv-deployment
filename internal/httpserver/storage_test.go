package httpserver

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

func TestStorageDeviceInventoryRequiresAuthenticationAndIsReadOnly(t *testing.T) {
	app := newTestApp(t)

	anonymous := requestJSON(t, app.handler, http.MethodGet, "/api/v1/storage/devices", "", nil, "")
	if anonymous.Code != http.StatusUnauthorized {
		t.Fatalf("anonymous status=%d body=%s", anonymous.Code, anonymous.Body.String())
	}

	cookie, _ := login(t, app, "admin", app.adminPassword)
	rr := requestJSON(t, app.handler, http.MethodGet, "/api/v1/storage/devices", "", cookie, "")
	if rr.Code != http.StatusOK {
		t.Fatalf("storage inventory status=%d body=%s", rr.Code, rr.Body.String())
	}

	var body struct {
		Count   int `json:"count"`
		Devices []struct {
			Name       string `json:"name"`
			DevicePath string `json:"device_path"`
			SizeBytes  uint64 `json:"size_bytes"`
			ReadOnly   bool   `json:"read_only"`
			Removable  bool   `json:"removable"`
		} `json:"devices"`
		Warnings []struct {
			Code   string `json:"code"`
			Device string `json:"device"`
		} `json:"warnings"`
		Management struct {
			InventorySupported   bool   `json:"inventory_supported"`
			Scope                string `json:"scope"`
			PartitionsSupported  bool   `json:"partitions_supported"`
			FilesystemsSupported bool   `json:"filesystems_supported"`
			MountsSupported      bool   `json:"mounts_supported"`
			PreviewSupported     bool   `json:"preview_supported"`
			PreflightSupported   bool   `json:"preflight_supported"`
			ApplySupported       bool   `json:"apply_supported"`
			Reason               string `json:"reason"`
		} `json:"management"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.Count != len(body.Devices) {
		t.Fatalf("count=%d devices=%d", body.Count, len(body.Devices))
	}
	for _, device := range body.Devices {
		if device.Name == "" || device.DevicePath != "/dev/"+device.Name || !strings.HasPrefix(device.DevicePath, "/dev/") {
			t.Fatalf("invalid device metadata: %+v", device)
		}
	}
	for _, warning := range body.Warnings {
		if warning.Code == "" || warning.Device == "" || strings.Contains(warning.Device, "/") {
			t.Fatalf("invalid bounded warning: %+v", warning)
		}
	}
	if !body.Management.InventorySupported || body.Management.Scope != "top_level_block_devices" || !body.Management.PartitionsSupported {
		t.Fatalf("unexpected inventory management metadata: %+v", body.Management)
	}
	if body.Management.FilesystemsSupported || body.Management.MountsSupported || body.Management.PreviewSupported || body.Management.PreflightSupported || body.Management.ApplySupported {
		t.Fatalf("storage mutation/scope unexpectedly advertised: %+v", body.Management)
	}
	if body.Management.Reason != "storage_mutation_not_implemented" {
		t.Fatalf("management reason=%q", body.Management.Reason)
	}
}
