package httpserver

import (
	"net/http"

	"github.com/ControlCenterSoft/srv-deployment/internal/auth"
	"github.com/ControlCenterSoft/srv-deployment/internal/operations"
	"github.com/ControlCenterSoft/srv-deployment/internal/state"
)

const revokeOtherSessionsAction = "auth.sessions.revoke_others"

func (s *Server) registerAuthSessionRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/auth/sessions/revoke-others", s.requireAuth(s.revokeOtherSessions))
}

func (s *Server) revokeOtherSessions(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	if !validMutation(r, sess) {
		s.auditEvent(r, u.Username, string(u.Role), revokeOtherSessionsAction, u.Username, "denied", "csrf_rejected")
		writeError(w, http.StatusForbidden, "csrf_rejected", "CSRF or origin validation failed", operationID(r))
		return
	}
	if !s.beginOperation(w, r, u, revokeOtherSessionsAction, u.Username) {
		return
	}

	cookie, err := r.Cookie("cc_session")
	if err != nil {
		s.finishOperation(r, u, revokeOtherSessionsAction, u.Username, operations.StatusFailed, "authentication_required")
		clearSessionCookie(w)
		writeError(w, http.StatusUnauthorized, "authentication_required", "Authentication required", operationID(r))
		return
	}

	revoked, ok := s.sessions.RevokeOtherSessions(u.Username, cookie.Value)
	if !ok {
		s.finishOperation(r, u, revokeOtherSessionsAction, u.Username, operations.StatusFailed, "authentication_required")
		clearSessionCookie(w)
		writeError(w, http.StatusUnauthorized, "authentication_required", "Authentication required", operationID(r))
		return
	}

	s.finishOperation(r, u, revokeOtherSessionsAction, u.Username, operations.StatusSucceeded, "")
	writeJSON(w, http.StatusOK, envelope{
		"status":        "other_sessions_revoked",
		"revoked_count": revoked,
	})
}
