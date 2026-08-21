package httpserver

import (
	"net/http"
	"strings"

	"github.com/ControlCenterSoft/srv-deployment/internal/auth"
	"github.com/ControlCenterSoft/srv-deployment/internal/operations"
	"github.com/ControlCenterSoft/srv-deployment/internal/state"
)

func (s *Server) registerFleetRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/fleet/nodes", s.requireAuth(s.listFleetNodes))
	mux.HandleFunc("POST /api/v1/fleet/nodes", s.requireAuth(s.createFleetNode))
}

func (s *Server) listFleetNodes(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	if u.Role != state.RoleAdmin && u.Role != state.RoleViewer {
		writeError(w, http.StatusForbidden, "permission_denied", "Permission denied", operationID(r))
		return
	}
	nodes := s.store.ListFleetNodes()
	pending := 0
	for _, node := range nodes {
		if node.Status == "pending_enrollment" {
			pending++
		}
	}
	writeJSON(w, http.StatusOK, envelope{
		"nodes":   nodes,
		"summary": envelope{"total": len(nodes), "pending_enrollment": pending},
	})
}

type createFleetNodeRequest struct {
	Name        string `json:"name"`
	Address     string `json:"address"`
	Group       string `json:"group"`
	Environment string `json:"environment"`
}

func (s *Server) createFleetNode(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	if u.Role != state.RoleAdmin {
		writeError(w, http.StatusForbidden, "permission_denied", "Permission denied", operationID(r))
		return
	}
	if !validMutation(r, sess) {
		s.auditEvent(r, u.Username, string(u.Role), "fleet.node.create", "", "denied", "csrf_rejected")
		writeError(w, http.StatusForbidden, "csrf_rejected", "CSRF or origin validation failed", operationID(r))
		return
	}
	var in createFleetNodeRequest
	if err := decodeJSON(r, &in); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "Invalid JSON request", operationID(r))
		return
	}
	target := strings.TrimSpace(in.Name)
	if !s.beginOperation(w, r, u, "fleet.node.create", target) {
		return
	}
	node, err := s.store.CreateFleetNode(in.Name, in.Address, in.Group, in.Environment)
	if err != nil {
		s.finishOperation(r, u, "fleet.node.create", target, operations.StatusFailed, "fleet_node_create_failed")
		writeError(w, http.StatusBadRequest, "fleet_node_create_failed", err.Error(), operationID(r))
		return
	}
	s.finishOperation(r, u, "fleet.node.create", node.ID, operations.StatusSucceeded, "")
	writeJSON(w, http.StatusCreated, envelope{"node": node})
}
