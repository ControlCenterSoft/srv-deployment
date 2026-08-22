package httpserver

import (
	"net/http"
	"regexp"
	"time"

	"github.com/ControlCenterSoft/srv-deployment/internal/auth"
	"github.com/ControlCenterSoft/srv-deployment/internal/observability"
	"github.com/ControlCenterSoft/srv-deployment/internal/state"
)

var operationLookupIDRE = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$`)

func (s *Server) requireOperationRead(next func(http.ResponseWriter, *http.Request, auth.Session, state.User)) http.HandlerFunc {
	return s.requireAuth(func(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
		id := r.PathValue("id")
		action := "operations.detail.read"
		if id == operationIncidentsCollectionID {
			action = "operations.incidents.read"
		}
		if !hasPermission(u.Role, "operations.read") {
			s.auditEvent(r, u.Username, string(u.Role), action, id, "denied", "permission_denied")
			writeError(w, http.StatusForbidden, "permission_denied", "Permission denied", operationID(r))
			return
		}
		next(w, r, sess, u)
	})
}

func (s *Server) operationDetail(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	id := r.PathValue("id")
	if id == operationIncidentsCollectionID {
		s.operationIncidents(w, r, sess, u)
		return
	}
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

	auditAuthorized := hasPermission(u.Role, "audit.read")
	auditHealthy := s.audit != nil
	auditAvailable := false
	auditErrorCode := ""
	auditEvents := []observability.AuditEvent{}
	if auditAuthorized && auditHealthy {
		correlated, err := s.audit.ForOperation(id, 100)
		if err != nil {
			auditHealthy = false
			auditErrorCode = "audit_unavailable"
			s.logger.Warn("operation audit correlation unavailable", "operation_id", operationID(r), "target_operation_id", id, "error", err)
		} else {
			auditEvents = correlated
			auditAvailable = true
		}
	}
	if auditAuthorized && !auditHealthy && auditErrorCode == "" {
		auditErrorCode = "audit_unavailable"
	}

	healthStatus := "healthy"
	if auditAuthorized && !auditHealthy {
		healthStatus = "degraded"
	}

	s.auditEvent(r, u.Username, string(u.Role), "operations.detail.read", id, "success", "")
	writeJSON(w, http.StatusOK, envelope{
		"contract_version": 1,
		"operation":        record,
		"audit": envelope{
			"events":     auditEvents,
			"count":      len(auditEvents),
			"available":  auditAvailable,
			"authorized": auditAuthorized,
			"bounded":    true,
			"limit":      100,
			"permission": "audit.read",
			"error_code": auditErrorCode,
		},
		"permissions": envelope{
			"read":  "operations.read",
			"audit": "audit.read",
		},
		"health": envelope{
			"status":          healthStatus,
			"operation_store": true,
			"audit_log":       auditHealthy,
		},
		"observed_at": time.Now().UTC().Format(time.RFC3339),
	})
}
