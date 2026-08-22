package httpserver

import (
	"net/http"
	"time"

	"github.com/ControlCenterSoft/srv-deployment/internal/auth"
	"github.com/ControlCenterSoft/srv-deployment/internal/state"
	storagemodel "github.com/ControlCenterSoft/srv-deployment/internal/storage"
)

func (s *Server) registerStorageRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/storage/devices", s.requirePermission("system.read", s.storageDevices))
}

func (s *Server) storageDevices(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	snapshot, err := storagemodel.Inventory()
	if err != nil {
		s.auditEvent(r, u.Username, string(u.Role), "storage.devices.read", "host", "failed", "storage_inventory_unavailable")
		writeError(w, http.StatusServiceUnavailable, "storage_inventory_unavailable", "Storage device inventory is unavailable", operationID(r))
		return
	}

	s.auditEvent(r, u.Username, string(u.Role), "storage.devices.read", "host", "success", "")
	writeJSON(w, http.StatusOK, envelope{
		"devices":     snapshot.Devices,
		"count":       len(snapshot.Devices),
		"warnings":    snapshot.Warnings,
		"observed_at": time.Now().UTC().Format(time.RFC3339),
		"management": envelope{
			"inventory_supported":   true,
			"scope":                 "top_level_block_devices",
			"partitions_supported":  false,
			"filesystems_supported": false,
			"mounts_supported":      false,
			"preview_supported":     false,
			"preflight_supported":   false,
			"apply_supported":       false,
			"reason":                "storage_mutation_not_implemented",
		},
	})
}
