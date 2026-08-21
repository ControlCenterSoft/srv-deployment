package httpserver

import (
	"net/http"
	"strings"
	"time"

	"github.com/ControlCenterSoft/srv-deployment/internal/auth"
	"github.com/ControlCenterSoft/srv-deployment/internal/operations"
	"github.com/ControlCenterSoft/srv-deployment/internal/state"
)

func (s *Server) registerFleetRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/fleet/nodes", s.requireAuth(s.listFleetNodes))
	mux.HandleFunc("POST /api/v1/fleet/nodes", s.requireAuth(s.createFleetNode))
	mux.HandleFunc("POST /api/v1/fleet/nodes/{id}/enrollment", s.requireAuth(s.prepareFleetEnrollment))
	mux.HandleFunc("POST /api/v1/fleet/enroll", s.enrollFleetNode)
}

func (s *Server) listFleetNodes(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	if u.Role != state.RoleAdmin && u.Role != state.RoleViewer {
		writeError(w, http.StatusForbidden, "permission_denied", "Permission denied", operationID(r))
		return
	}
	nodes := s.store.ListFleetNodes()
	publicNodes := make([]state.FleetNode, 0, len(nodes))
	pending := 0
	enrolled := 0
	for _, node := range nodes {
		publicNodes = append(publicNodes, node.Public())
		switch node.Status {
		case "pending_enrollment", "enrollment_ready":
			pending++
		case "enrolled":
			enrolled++
		}
	}
	writeJSON(w, http.StatusOK, envelope{
		"nodes": publicNodes,
		"summary": envelope{
			"total": len(publicNodes), "pending_enrollment": pending, "enrolled": enrolled,
		},
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

func (s *Server) prepareFleetEnrollment(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	if u.Role != state.RoleAdmin {
		writeError(w, http.StatusForbidden, "permission_denied", "Permission denied", operationID(r))
		return
	}
	if !validMutation(r, sess) {
		s.auditEvent(r, u.Username, string(u.Role), "fleet.node.enrollment.prepare", r.PathValue("id"), "denied", "csrf_rejected")
		writeError(w, http.StatusForbidden, "csrf_rejected", "CSRF or origin validation failed", operationID(r))
		return
	}
	id := strings.TrimSpace(r.PathValue("id"))
	if !s.beginOperation(w, r, u, "fleet.node.enrollment.prepare", id) {
		return
	}
	node, token, err := s.store.PrepareFleetEnrollment(id, 15*time.Minute)
	if err != nil {
		s.finishOperation(r, u, "fleet.node.enrollment.prepare", id, operations.StatusFailed, "fleet_enrollment_prepare_failed")
		writeError(w, http.StatusBadRequest, "fleet_enrollment_prepare_failed", err.Error(), operationID(r))
		return
	}
	s.finishOperation(r, u, "fleet.node.enrollment.prepare", node.ID, operations.StatusSucceeded, "")
	writeJSON(w, http.StatusCreated, envelope{
		"node": node,
		"enrollment": envelope{
			"token": token, "expires_at": node.EnrollmentExpiresAt, "one_time": true,
		},
	})
}

type enrollFleetNodeRequest struct {
	NodeID       string `json:"node_id"`
	Token        string `json:"token"`
	AgentVersion string `json:"agent_version"`
}

func (s *Server) enrollFleetNode(w http.ResponseWriter, r *http.Request) {
	var in enrollFleetNodeRequest
	if err := decodeJSON(r, &in); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "Invalid JSON request", operationID(r))
		return
	}
	node, err := s.store.EnrollFleetNode(in.NodeID, in.Token, in.AgentVersion)
	if err != nil {
		s.auditEvent(r, "fleet-agent", "agent", "fleet.node.enroll", strings.TrimSpace(in.NodeID), "denied", "invalid_enrollment_credential")
		writeError(w, http.StatusUnauthorized, "invalid_enrollment_credential", "Invalid or expired enrollment credential", operationID(r))
		return
	}
	s.auditEvent(r, "fleet-agent:"+node.ID, "agent", "fleet.node.enroll", node.ID, "succeeded", "")
	writeJSON(w, http.StatusOK, envelope{"node": node})
}
