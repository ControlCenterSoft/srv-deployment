package httpserver

import (
	"net/http"
	"regexp"
	"time"

	"github.com/ControlCenterSoft/srv-deployment/internal/auth"
	"github.com/ControlCenterSoft/srv-deployment/internal/state"
)

var operationLookupIDRE = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$`)

func (s *Server) requireOperationRead(next func(http.ResponseWriter, *http.Request, auth.Session, state.User)) http.HandlerFunc {
	return s.requireAuth(func(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
		id := r.PathValue("id")
		if !hasPermission(u.Role, "operations.read") {
			s.auditEvent(r, u.Username, string(u.Role), "operations.detail.read", id, "denied", "permission_denied")
			writeError(w, http.StatusForbidden, "permission_denied", "Permission denied", operationID(r))
			return
		}
		next(w, r, sess, u)
	})
}

func (s *Server) operationDetail(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	id := r.PathValue("id")
	if !operationLookupIDRE.MatchString(id) {
		s.auditEvent(r, u.Username, string(u.Role), "operations.detail.read", id, "failed", "invalid_operation_id")
		writeError(w, http.StatusBadRequest, "invalid_operation_id", "Operation ID is invalid", operationID(r))
		return
	}
	record, ok := s.operations.Get(id)
	if !ok {
		s.auditEvent(r, u.Username, string(u.Role), "operations.detail.read", id, "failed", "operation_not_found")
		writeError(w, http.StatusNotFound, "operation_not_found", "Operation not found", operationID(r))
		return
	}
	s.auditEvent(r, u.Username, string(u.Role), "operations.detail.read", id, "success", "")
	writeJSON(w, http.StatusOK, envelope{
		"contract_version": 1,
		"operation":        record,
		"permissions": envelope{
			"read": "operations.read",
		},
		"health": envelope{
			"status":          "healthy",
			"operation_store": true,
		},
		"observed_at": time.Now().UTC().Format(time.RFC3339),
	})
}
