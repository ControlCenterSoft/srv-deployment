package httpserver

import (
	"net/http"

	"github.com/ControlCenterSoft/srv-deployment/internal/auth"
	networkmodel "github.com/ControlCenterSoft/srv-deployment/internal/network"
	"github.com/ControlCenterSoft/srv-deployment/internal/state"
)

func (s *Server) registerNetworkRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/network/address-change/preview", s.requireAuth(s.networkAddressChangePreview))
	s.registerDNSRoutes(mux)
}

func (s *Server) networkAddressChangePreview(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	if u.Role != state.RoleAdmin {
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
	s.auditEvent(r, u.Username, string(u.Role), "network.address.preview", plan.Interface, "success", "")
	writeJSON(w, http.StatusOK, envelope{
		"plan":     plan,
		"desired":  envelope{"interface": plan.Interface, "cidr": plan.DesiredCIDR},
		"actual":   envelope{"addresses": plan.ActualAddresses},
		"rollback": envelope{"addresses": plan.RollbackAddresses},
	})
}
