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
		"actual": resolver,
		"desired": nil,
		"management": envelope{
			"supported": false,
			"reason":    "read_only_foundation",
		},
		"observed_at": time.Now().UTC().Format(time.RFC3339),
	})
}
