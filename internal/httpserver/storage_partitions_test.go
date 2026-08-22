package httpserver

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

func TestStoragePartitionInventoryRequiresAuthenticationAndRemainsReadOnly(t *testing.T) {
	app := newTestApp(t)

	anonymous := requestJSON(t, app.handler, http.MethodGet, "/api/v1/storage/partitions", "", nil, "")
	if anonymous.Code != http.StatusUnauthorized {
		t.Fatalf("anonymous status=%d body=%s", anonymous.Code, anonymous.Body.String())
	}

	cookie, _ := login(t, app, "admin", app.adminPassword)
	rr := requestJSON(t, app.handler, http.MethodGet, "/api/v1/storage/partitions", "", cookie, "")
	if rr.Code != http.StatusOK {
		t.Fatalf("storage partition inventory status=%d body=%s", rr.Code, rr.Body.String())
	}

	var body struct {
		Count      int `json:"count"`
		Partitions []struct {
			Name            string `json:"name"`
			DevicePath      string `json:"device_path"`
			Parent          string `json:"parent"`
			PartitionNumber uint64 `json:"partition_number"`
			StartBytes      uint64 `json:"start_bytes"`
			SizeBytes       uint64 `json:"size_bytes"`
		} `json:"partitions"`
		Warnings []struct {
			Code      string `json:"code"`
			Device    string `json:"device"`
			Partition string `json:"partition"`
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
	if body.Count != len(body.Partitions) {
		t.Fatalf("count=%d partitions=%d", body.Count, len(body.Partitions))
	}
	for _, partition := range body.Partitions {
		if partition.Name == "" || partition.Parent == "" || partition.PartitionNumber == 0 || partition.DevicePath != "/dev/"+partition.Name || strings.Contains(partition.Name, "/") || strings.Contains(partition.Parent, "/") {
			t.Fatalf("invalid partition metadata: %+v", partition)
		}
	}
	for _, warning := range body.Warnings {
		if warning.Code == "" || warning.Device == "" || strings.Contains(warning.Device, "/") || strings.Contains(warning.Partition, "/") {
			t.Fatalf("invalid bounded warning: %+v", warning)
		}
	}
	if !body.Management.InventorySupported || !body.Management.PartitionsSupported || body.Management.Scope != "block_device_partitions" {
		t.Fatalf("unexpected partition management metadata: %+v", body.Management)
	}
	if body.Management.FilesystemsSupported || body.Management.MountsSupported || body.Management.PreviewSupported || body.Management.PreflightSupported || body.Management.ApplySupported {
		t.Fatalf("storage mutation/scope unexpectedly advertised: %+v", body.Management)
	}
	if body.Management.Reason != "storage_mutation_not_implemented" {
		t.Fatalf("management reason=%q", body.Management.Reason)
	}
}
