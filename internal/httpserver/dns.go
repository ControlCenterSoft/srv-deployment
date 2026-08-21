package httpserver

import (
	"net/http"
	"time"

	"github.com/ControlCenterSoft/srv-deployment/internal/auth"
	dnsmodel "github.com/ControlCenterSoft/srv-deployment/internal/dns"
	"github.com/ControlCenterSoft/srv-deployment/internal/state"
)

func (s *Server) registerDNSRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/dns/resolver", s.requirePermission("system.read", s.dnsResolverInventory))
	mux.HandleFunc("POST /api/v1/dns/resolver/preview", s.requireAuth(s.dnsResolverPreview))
}

func (s *Server) dnsResolverInventory(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	resolver, err := dnsmodel.Inventory()
	if err != nil {
		s.auditEvent(r, u.Username, string(u.Role), "dns.resolver.read", "host", "failed", "dns_resolver_unavailable")
		writeError(w, http.StatusServiceUnavailable, "dns_resolver_unavailable", "DNS resolver state is unavailable", operationID(r))
		return
	}
	s.auditEvent(r, u.Username, string(u.Role), "dns.resolver.read", "host", "success", "")
	writeJSON(w, http.StatusOK, envelope{
		"actual":  resolver,
		"desired": nil,
		"management": envelope{
			"supported":         false,
			"preview_supported": true,
			"apply_supported":   false,
			"reason":            "recovery_executor_not_implemented",
		},
		"observed_at": time.Now().UTC().Format(time.RFC3339),
	})
}

func (s *Server) dnsResolverPreview(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	if u.Role != state.RoleAdmin {
		writeError(w, http.StatusForbidden, "permission_denied", "Permission denied", operationID(r))
		return
	}
	if !validMutation(r, sess) {
		s.auditEvent(r, u.Username, string(u.Role), "dns.resolver.preview", "host", "denied", "csrf_rejected")
		writeError(w, http.StatusForbidden, "csrf_rejected", "CSRF or origin validation failed", operationID(r))
		return
	}
	var in dnsmodel.ResolverChangeRequest
	if err := decodeJSON(r, &in); err != nil {
		s.auditEvent(r, u.Username, string(u.Role), "dns.resolver.preview", "host", "failed", "invalid_request")
		writeError(w, http.StatusBadRequest, "invalid_request", "Invalid JSON request", operationID(r))
		return
	}
	actual, err := dnsmodel.Inventory()
	if err != nil {
		s.auditEvent(r, u.Username, string(u.Role), "dns.resolver.preview", "host", "failed", "dns_resolver_unavailable")
		writeError(w, http.StatusServiceUnavailable, "dns_resolver_unavailable", "DNS resolver state is unavailable", operationID(r))
		return
	}
	plan, err := dnsmodel.PreviewResolverChange(in, actual)
	if err != nil {
		s.auditEvent(r, u.Username, string(u.Role), "dns.resolver.preview", "host", "failed", "dns_validation_failed")
		writeError(w, http.StatusBadRequest, "dns_validation_failed", err.Error(), operationID(r))
		return
	}
	s.auditEvent(r, u.Username, string(u.Role), "dns.resolver.preview", "host", "success", "")
	writeJSON(w, http.StatusOK, envelope{
		"plan":     plan,
		"desired":  plan.Desired,
		"actual":   plan.Actual,
		"rollback": plan.Rollback,
		"management": envelope{
			"preview_supported": true,
			"apply_supported":   false,
			"reason":            "recovery_executor_not_implemented",
		},
	})
}
