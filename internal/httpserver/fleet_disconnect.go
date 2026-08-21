package httpserver

import (
	"net/http"
	"strings"

	"github.com/ControlCenterSoft/srv-deployment/internal/auth"
	"github.com/ControlCenterSoft/srv-deployment/internal/operations"
	"github.com/ControlCenterSoft/srv-deployment/internal/state"
)

func (s *Server) disconnectFleetNode(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	if u.Role != state.RoleAdmin {
		writeError(w, http.StatusForbidden, "permission_denied", "Permission denied", operationID(r))
		return
	}
	id := strings.TrimSpace(r.PathValue("id"))
	if !validMutation(r, sess) {
		s.auditEvent(r, u.Username, string(u.Role), "fleet.node.disconnect", id, "denied", "csrf_rejected")
		writeError(w, http.StatusForbidden, "csrf_rejected", "CSRF or origin validation failed", operationID(r))
		return
	}
	if !s.beginOperation(w, r, u, "fleet.node.disconnect", id) {
		return
	}

	node, changed, err := s.store.DisconnectFleetNode(id)
	if err != nil {
		s.finishOperation(r, u, "fleet.node.disconnect", id, operations.StatusFailed, "fleet_node_disconnect_failed")
		writeError(w, http.StatusBadRequest, "fleet_node_disconnect_failed", err.Error(), operationID(r))
		return
	}
	s.finishOperation(r, u, "fleet.node.disconnect", node.ID, operations.StatusSucceeded, "")
	writeJSON(w, http.StatusOK, envelope{
		"node":                     node,
		"disconnected":             changed,
		"agent_credential_revoked": true,
		"enrollment_token_revoked": true,
		"re_enrollment_required":   true,
		"remote_host_changed":      false,
	})
}
