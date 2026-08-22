package httpserver

import (
	"net/http"

	"github.com/ControlCenterSoft/srv-deployment/internal/auth"
	networkmodel "github.com/ControlCenterSoft/srv-deployment/internal/network"
	"github.com/ControlCenterSoft/srv-deployment/internal/state"
)

func (s *Server) registerNetworkRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/network/address-change/preview", s.requireAuth(s.networkAddressChangePreview))
	mux.HandleFunc("POST /api/v1/network/address-change/preflight", s.requireAuth(s.networkAddressChangePreflight))
	s.registerDNSRoutes(mux)
	s.registerStorageRoutes(mux)
}

func (s *Server) networkAddressChangePreview(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	if u.Role != state.RoleAdmin {
		s.auditEvent(r, u.Username, string(u.Role), "network.address.preview", "host", "denied", "permission_denied")
		writeError(w, http.StatusForbidden, "permission_denied", "Permission denied", operationID(r))
		return
	}
	if !validMutation(r, sess) {
		s.auditEvent(r, u.Username, string(u.Role), "network.address.preview", "host", "denied", "csrf_rejected")
		writeError(w, http.StatusForbidden, "csrf_rejected", "CSRF or origin validation failed", operationID(r))
		return
	}
	var in networkmodel.AddressChangeRequest
	if err := decodeJSON(r, &in); err != nil {
		s.auditEvent(r, u.Username, string(u.Role), "network.address.preview", "host", "failed", "invalid_request")
		writeError(w, http.StatusBadRequest, "invalid_request", "Invalid JSON request", operationID(r))
		return
	}
	interfaces, err := networkmodel.Inventory()
	if err != nil {
		s.auditEvent(r, u.Username, string(u.Role), "network.address.preview", in.Interface, "failed", "network_inventory_unavailable")
		writeError(w, http.StatusServiceUnavailable, "network_inventory_unavailable", "Network interface inventory is unavailable", operationID(r))
		return
	}
	plan, err := networkmodel.PreviewAddressChange(in, interfaces)
	if err != nil {
		s.auditEvent(r, u.Username, string(u.Role), "network.address.preview", in.Interface, "failed", "network_validation_failed")
		writeError(w, http.StatusBadRequest, "network_validation_failed", err.Error(), operationID(r))
		return
	}
	sourceFingerprint := networkmodel.InterfaceFingerprintForName(interfaces, plan.Interface)
	if sourceFingerprint == "" {
		s.auditEvent(r, u.Username, string(u.Role), "network.address.preview", plan.Interface, "failed", "network_preflight_unavailable")
		writeError(w, http.StatusServiceUnavailable, "network_preflight_unavailable", "Network address preflight fingerprint is unavailable", operationID(r))
		return
	}
	s.auditEvent(r, u.Username, string(u.Role), "network.address.preview", plan.Interface, "success", "")
	writeJSON(w, http.StatusOK, envelope{
		"plan":               plan,
		"source_fingerprint": sourceFingerprint,
		"desired":            envelope{"interface": plan.Interface, "cidr": plan.DesiredCIDR},
		"actual":             envelope{"addresses": plan.ActualAddresses},
		"rollback":           envelope{"addresses": plan.RollbackAddresses},
		"management": envelope{
			"preview_supported":   true,
			"preflight_supported": true,
			"apply_supported":     false,
			"reason":              "recovery_executor_not_implemented",
		},
	})
}

func (s *Server) networkAddressChangePreflight(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	if u.Role != state.RoleAdmin {
		s.auditEvent(r, u.Username, string(u.Role), "network.address.preflight", "host", "denied", "permission_denied")
		writeError(w, http.StatusForbidden, "permission_denied", "Permission denied", operationID(r))
		return
	}
	if !validMutation(r, sess) {
		s.auditEvent(r, u.Username, string(u.Role), "network.address.preflight", "host", "denied", "csrf_rejected")
		writeError(w, http.StatusForbidden, "csrf_rejected", "CSRF or origin validation failed", operationID(r))
		return
	}
	var in networkmodel.AddressPreflightRequest
	if err := decodeJSON(r, &in); err != nil {
		s.auditEvent(r, u.Username, string(u.Role), "network.address.preflight", "host", "failed", "invalid_request")
		writeError(w, http.StatusBadRequest, "invalid_request", "Invalid JSON request", operationID(r))
		return
	}
	interfaces, err := networkmodel.Inventory()
	if err != nil {
		s.auditEvent(r, u.Username, string(u.Role), "network.address.preflight", in.Interface, "failed", "network_inventory_unavailable")
		writeError(w, http.StatusServiceUnavailable, "network_inventory_unavailable", "Network interface inventory is unavailable", operationID(r))
		return
	}
	preflight, err := networkmodel.PreflightAddressChange(in, interfaces)
	if err != nil {
		s.auditEvent(r, u.Username, string(u.Role), "network.address.preflight", in.Interface, "failed", "network_validation_failed")
		writeError(w, http.StatusBadRequest, "network_validation_failed", err.Error(), operationID(r))
		return
	}
	result := "success"
	errorCode := ""
	if !preflight.Passed {
		result = "failed"
		errorCode = "network_preflight_failed"
	}
	s.auditEvent(r, u.Username, string(u.Role), "network.address.preflight", preflight.Interface, result, errorCode)
	writeJSON(w, http.StatusOK, envelope{
		"preflight": preflight,
		"desired":   envelope{"interface": preflight.Interface, "cidr": preflight.DesiredCIDR},
		"actual":    envelope{"addresses": preflight.ActualAddresses},
		"rollback":  envelope{"addresses": preflight.RollbackAddresses},
		"management": envelope{
			"preview_supported":   true,
			"preflight_supported": true,
			"apply_supported":     false,
			"reason":              "recovery_executor_not_implemented",
		},
	})
}
