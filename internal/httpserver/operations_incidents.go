package httpserver

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/ControlCenterSoft/srv-deployment/internal/auth"
	"github.com/ControlCenterSoft/srv-deployment/internal/operations"
	"github.com/ControlCenterSoft/srv-deployment/internal/state"
)

const defaultIncidentLimit = 50

func (s *Server) operationIncidents(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	limit, ok := parseIncidentLimit(r)
	if !ok {
		s.auditEvent(r, u.Username, string(u.Role), "operations.incidents.read", "incidents", "failed", "invalid_limit")
		writeError(w, http.StatusBadRequest, "invalid_limit", "Limit must be an integer from 1 to 100", operationID(r))
		return
	}
	if s.operations == nil {
		s.auditEvent(r, u.Username, string(u.Role), "operations.incidents.read", "incidents", "failed", "operation_store_unavailable")
		writeError(w, http.StatusServiceUnavailable, "operation_store_unavailable", "Operation tracking is unavailable", operationID(r))
		return
	}

	incidents := s.operations.Incidents(limit)
	auditHealthy := s.audit != nil
	healthStatus := "healthy"
	if !auditHealthy {
		healthStatus = "degraded"
	}

	s.auditEvent(r, u.Username, string(u.Role), "operations.incidents.read", "incidents", "success", "")
	writeJSON(w, http.StatusOK, envelope{
		"contract_version": 1,
		"incidents":        incidents,
		"count":            len(incidents),
		"bounded":          true,
		"limit":            limit,
		"statuses":         []operations.Status{operations.StatusFailed, operations.StatusInterrupted},
		"permissions": envelope{
			"read": "operations.read",
		},
		"health": envelope{
			"status":          healthStatus,
			"operation_store": true,
			"audit_log":       auditHealthy,
		},
		"observed_at": time.Now().UTC().Format(time.RFC3339),
	})
}

func parseIncidentLimit(r *http.Request) (int, bool) {
	values, present := r.URL.Query()["limit"]
	if !present {
		return defaultIncidentLimit, true
	}
	if len(values) != 1 {
		return 0, false
	}
	raw := strings.TrimSpace(values[0])
	if raw == "" {
		return 0, false
	}
	limit, err := strconv.Atoi(raw)
	if err != nil || limit < 1 || limit > 100 {
		return 0, false
	}
	return limit, true
}
