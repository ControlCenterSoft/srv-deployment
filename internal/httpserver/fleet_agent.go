package httpserver

import (
	"crypto/sha256"
	_ "embed"
	"encoding/hex"
	"net/http"
	"strings"

	"github.com/ControlCenterSoft/srv-deployment/internal/auth"
	"github.com/ControlCenterSoft/srv-deployment/internal/state"
)

const fleetAgentVersion = "1.1.0"

//go:embed assets/control-center-fleet-agent.py
var fleetAgentSource []byte

//go:embed assets/install-fleet-agent.sh
var fleetAgentInstallerTemplate string

func fleetAgentDigest() string {
	digest := sha256.Sum256(fleetAgentSource)
	return hex.EncodeToString(digest[:])
}

func fleetAgentInstaller() string {
	return strings.ReplaceAll(fleetAgentInstallerTemplate, "__AGENT_SHA256__", fleetAgentDigest())
}

func fleetAgentSetupEnvelope() envelope {
	return envelope{
		"version":                    fleetAgentVersion,
		"install_path":               "/api/v1/fleet/agent/install.sh",
		"source_path":                "/api/v1/fleet/agent/agent.py",
		"heartbeat_interval_seconds": 60,
		"requires_https":             true,
		"loopback_http_for_testing":  true,
		"runtime_user":               "control-center-fleet",
		"arbitrary_shell":            false,
		"credential_shown_once":      true,
		"token_delivery":             "interactive_prompt_or_root_only_file",
	}
}

func (s *Server) registerFleetAgentRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/fleet/capabilities", s.requireAuth(s.fleetCapabilities))
	mux.HandleFunc("POST /api/v1/fleet/nodes/{id}/disconnect", s.requireAuth(s.disconnectFleetNode))
	mux.HandleFunc("GET /api/v1/fleet/agent/install.sh", s.serveFleetAgentInstaller)
	mux.HandleFunc("GET /api/v1/fleet/agent/agent.py", s.serveFleetAgentSource)
}

func (s *Server) fleetCapabilities(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	if u.Role != state.RoleAdmin && u.Role != state.RoleViewer {
		writeError(w, http.StatusForbidden, "permission_denied", "Permission denied", operationID(r))
		return
	}
	writeJSON(w, http.StatusOK, envelope{
		"contract_version": 1,
		"capability":       "fleet",
		"permissions": envelope{
			"read":               []string{string(state.RoleAdmin), string(state.RoleViewer)},
			"node_create":        []string{string(state.RoleAdmin)},
			"node_disconnect":    []string{string(state.RoleAdmin)},
			"enrollment_prepare": []string{string(state.RoleAdmin)},
			"agent_enroll":       "one_time_enrollment_token",
			"agent_heartbeat":    "agent_bearer_credential",
		},
		"agent": fleetAgentSetupEnvelope(),
		"health": envelope{
			"healthy_max_age_seconds": 120,
			"stale_max_age_seconds":   900,
			"states":                  []string{"healthy", "stale", "offline", "unknown"},
		},
	})
}

func (s *Server) serveFleetAgentInstaller(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/x-shellscript; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("X-Control-Center-Fleet-Agent-Version", fleetAgentVersion)
	w.Header().Set("X-Control-Center-Fleet-Agent-SHA256", fleetAgentDigest())
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(fleetAgentInstaller()))
}

func (s *Server) serveFleetAgentSource(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/x-python; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("X-Control-Center-Fleet-Agent-Version", fleetAgentVersion)
	w.Header().Set("X-Control-Center-Fleet-Agent-SHA256", fleetAgentDigest())
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(fleetAgentSource)
}
