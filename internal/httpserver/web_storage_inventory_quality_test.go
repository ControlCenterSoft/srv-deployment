package httpserver

import (
	"strings"
	"testing"
)

func TestAdminWebStorageInventoryLiveRegionIsBounded(t *testing.T) {
	index := readWebAsset(t, "web/index.html")
	storage := readWebAsset(t, "web/storage.js")

	if !strings.Contains(index, `<div id="storage-devices" hidden></div>`) {
		t.Fatal("storage inventory container must stay neutral instead of making the full dynamic inventory a live region")
	}
	if strings.Contains(index, `id="storage-devices" role="status"`) || strings.Contains(index, `id="storage-devices" aria-live=`) {
		t.Fatal("full storage inventory must not be exposed as a live region")
	}
	if strings.Contains(storage, `container.setAttribute("aria-live"`) || strings.Contains(storage, `container.role = "status"`) {
		t.Fatal("storage renderer must not promote the full device/warning/capability subtree into a live region")
	}

	for _, required := range []string{
		`status.role = "status"`,
		`status.setAttribute("aria-live", "polite")`,
		`summary.role = "status"`,
		`summary.setAttribute("aria-live", "polite")`,
		`message.role = "alert"`,
	} {
		if !strings.Contains(storage, required) {
			t.Fatalf("storage inventory must keep bounded loading/result/error announcement semantics %q", required)
		}
	}
}
