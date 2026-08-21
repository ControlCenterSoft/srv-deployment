package httpserver

import (
	"net/http"
	"strings"
	"time"

	"github.com/ControlCenterSoft/srv-deployment/internal/auth"
	"github.com/ControlCenterSoft/srv-deployment/internal/operations"
	"github.com/ControlCenterSoft/srv-deployment/internal/state"
)

const fleetOnlineWindow = 2 * time.Minute
const fleetStaleWindow = 15 * time.Minute

func (s *Server) registerFleetRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/fleet/nodes", s.requireAuth(s.listFleetNodes))
	mux.HandleFunc("POST /api/v1/fleet/nodes", s.requireAuth(s.createFleetNode))
	mux.HandleFunc("POST /api/v1/fleet/nodes/{id}/enrollment", s.requireAuth(s.prepareFleetEnrollment))
	mux.HandleFunc("POST /api/v1/fleet/enroll", s.enrollFleetNode)
	mux.HandleFunc("POST /api/v1/fleet/heartbeat", s.fleetHeartbeat)
	s.registerNetworkRoutes(mux)
}

func fleetHealth(node state.FleetNode, now time.Time) string {
	if node.Status != "enrolled" || node.LastSeenAt == nil {
		return "unknown"
	}
	age := now.Sub(*node.LastSeenAt)
	if age <= fleetOnlineWindow {
		return "healthy"
	}
	if age <= fleetStaleWindow {
		return "stale"
	}
	return "offline"
}

type fleetNodePublicView struct {
	state.FleetNode
	Health             string `json:"health"`
	LastSeenSecondsAgo *int64 `json:"last_seen_seconds_ago,omitempty"`
}

func fleetNodeView(node state.FleetNode, now time.Time) fleetNodePublicView {
	public := node.Public()
	view := fleetNodePublicView{FleetNode: public, Health: fleetHealth(public, now)}
	if public.LastSeenAt != nil {
		age := now.Sub(*public.LastSeenAt).Seconds()
		if age < 0 {
			age = 0
		}
		seconds := int64(age)
		view.LastSeenSecondsAgo = &seconds
	}
	return view
}

func (s *Server) listFleetNodes(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	if u.Role != state.RoleAdmin && u.Role != state.RoleViewer {
		writeError(w, http.StatusForbidden, "permission_denied", "Permission denied", operationID(r))
		return
	}
	nodes := s.store.ListFleetNodes()
	now := time.Now().UTC()
	views := make([]fleetNodePublicView, 0, len(nodes))
	pending, enrolled, healthy, stale, offline := 0, 0, 0, 0, 0
	for _, node := range nodes {
		views = append(views, fleetNodeView(node, now))
		switch node.Status {
		case "pending_enrollment", "enrollment_ready":
			pending++
		case "enrolled":
			enrolled++
		}
		switch fleetHealth(node, now) {
		case "healthy":
			healthy++
		case "stale":
			stale++
		case "offline":
			offline++
		}
	}
	writeJSON(w, http.StatusOK, envelope{
		"nodes":       views,
		"observed_at": now.Format(time.RFC3339),
		"summary": envelope{
			"total":              len(nodes),
			"pending_enrollment": pending,
			"enrolled":           enrolled,
			"healthy":            healthy,
			"stale":              stale,
			"offline":            offline,
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
			"token":      token,
			"expires_at": node.EnrollmentExpiresAt,
			"one_time":   true,
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
	node, credential, err := s.store.EnrollFleetNode(in.NodeID, in.Token, in.AgentVersion)
	if err != nil {
		s.auditEvent(r, "fleet-agent", "agent", "fleet.node.enroll", strings.TrimSpace(in.NodeID), "denied", "invalid_enrollment_credential")
		writeError(w, http.StatusUnauthorized, "invalid_enrollment_credential", "Invalid or expired enrollment credential", operationID(r))
		return
	}
	s.auditEvent(r, "fleet-agent:"+node.ID, "agent", "fleet.node.enroll", node.ID, "succeeded", "")
	writeJSON(w, http.StatusOK, envelope{
		"node":                  node,
		"agent_credential":      credential,
		"credential_type":       "bearer",
		"credential_shown_once": true,
	})
}

type fleetHeartbeatRequest struct {
	NodeID       string `json:"node_id"`
	AgentVersion string `json:"agent_version"`
	Hostname     string `json:"hostname"`
	OSName       string `json:"os_name"`
	OSVersion    string `json:"os_version"`
	Architecture string `json:"architecture"`
}

func (s *Server) fleetHeartbeat(w http.ResponseWriter, r *http.Request) {
	var in fleetHeartbeatRequest
	if err := decodeJSON(r, &in); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "Invalid JSON request", operationID(r))
		return
	}
	authz := strings.TrimSpace(r.Header.Get("Authorization"))
	credential := ""
	if len(authz) > 7 && strings.EqualFold(authz[:7], "Bearer ") {
		credential = strings.TrimSpace(authz[7:])
	}
	node, err := s.store.RecordFleetHeartbeat(in.NodeID, credential, state.FleetHeartbeat{
		AgentVersion: in.AgentVersion,
		Hostname:     in.Hostname,
		OSName:       in.OSName,
		OSVersion:    in.OSVersion,
		Architecture: in.Architecture,
	})
	if err != nil {
		s.auditEvent(r, "fleet-agent", "agent", "fleet.node.heartbeat", strings.TrimSpace(in.NodeID), "denied", "invalid_agent_credential")
		writeError(w, http.StatusUnauthorized, "invalid_agent_credential", "Invalid agent credential", operationID(r))
		return
	}
	s.auditEvent(r, "fleet-agent:"+node.ID, "agent", "fleet.node.heartbeat", node.ID, "success", "")
	writeJSON(w, http.StatusOK, envelope{
		"node":                   node,
		"health":                 "healthy",
		"accepted_at":            time.Now().UTC().Format(time.RFC3339),
		"next_heartbeat_seconds": 60,
	})
}
