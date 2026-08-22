package httpserver

import (
	"crypto/rand"
	"embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"log/slog"
	"net"
	"net/http"
	"net/url"
	"os"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/ControlCenterSoft/srv-deployment/internal/auth"
	"github.com/ControlCenterSoft/srv-deployment/internal/buildinfo"
	"github.com/ControlCenterSoft/srv-deployment/internal/diagnostics"
	networkmodel "github.com/ControlCenterSoft/srv-deployment/internal/network"
	"github.com/ControlCenterSoft/srv-deployment/internal/observability"
	"github.com/ControlCenterSoft/srv-deployment/internal/operations"
	"github.com/ControlCenterSoft/srv-deployment/internal/state"
)

//go:embed web/*
var webFS embed.FS

type envelope map[string]any

type Server struct {
	logger     *slog.Logger
	store      *state.Store
	operations *operations.Store
	audit      *observability.AuditLog
	sessions   *auth.Manager
	limiter    *auth.LoginLimiter
	startedAt  time.Time
}

func New(logger *slog.Logger, store *state.Store, opStore *operations.Store, audit *observability.AuditLog) http.Handler {
	s := &Server{
		logger: logger, store: store, operations: opStore, audit: audit,
		sessions: auth.NewManager(12 * time.Hour), limiter: auth.NewLoginLimiter(5, 5*time.Minute), startedAt: time.Now().UTC(),
	}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v1/health", s.health)
	mux.HandleFunc("GET /api/v1/readiness", s.readiness)
	mux.HandleFunc("GET /api/v1/version", s.version)
	mux.HandleFunc("POST /api/v1/auth/login", s.login)
	mux.HandleFunc("GET /api/v1/auth/session", s.session)
	mux.HandleFunc("POST /api/v1/auth/logout", s.requireAuth(s.logout))
	mux.HandleFunc("POST /api/v1/auth/password", s.requireAuth(s.changePassword))
	mux.HandleFunc("GET /api/v1/system/status", s.requirePermission("system.read", s.systemStatus))
	mux.HandleFunc("GET /api/v1/network/interfaces", s.requirePermission("system.read", s.networkInterfaces))
	mux.HandleFunc("GET /api/v1/rbac/users", s.requirePermission("rbac.users.read", s.listUsers))
	mux.HandleFunc("POST /api/v1/rbac/users", s.requirePermission("rbac.users.write", s.createUser))
	mux.HandleFunc("POST /api/v1/rbac/users/{username}/blocked", s.requirePermission("rbac.users.write", s.setBlocked))
	s.registerFleetRoutes(mux)
	mux.HandleFunc("GET /api/v1/operations", s.requirePermission("operations.read", s.listOperations))
	mux.HandleFunc("GET /api/v1/operations/{id}", s.requireOperationRead(s.operationDetail))
	mux.HandleFunc("GET /api/v1/audit", s.requirePermission("audit.read", s.listAudit))
	mux.HandleFunc("GET /api/v1/diagnostics/summary", s.requirePermission("system.read", s.diagnosticsSummary))
	mux.HandleFunc("GET /api/v1/diagnostics/export", s.requirePermission("diagnostics.export", s.diagnosticsExport))
	mux.HandleFunc("/api/", func(w http.ResponseWriter, r *http.Request) {
		writeError(w, http.StatusNotFound, "api_not_found", "API endpoint not found", operationID(r))
	})

	static, err := fs.Sub(webFS, "web")
	if err != nil {
		panic(err)
	}
	mux.Handle("/", http.FileServer(http.FS(static)))
	return requestMiddleware(logger, mux)
}

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, envelope{"status": "ok", "service": "control-center", "time": time.Now().UTC().Format(time.RFC3339)})
}

func (s *Server) readiness(w http.ResponseWriter, r *http.Request) {
	ready, detail := s.store.Ready()
	status := http.StatusOK
	if !ready {
		status = http.StatusServiceUnavailable
	}
	writeJSON(w, status, envelope{"status": detail, "ready": ready, "checks": []any{envelope{"name": "active_admin", "ok": ready}, envelope{"name": "operation_store", "ok": s.operations != nil}, envelope{"name": "audit_log", "ok": s.audit != nil}}})
}

func (s *Server) version(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, envelope{"product": "Control Center", "version": buildinfo.Version, "commit": buildinfo.Commit, "built_at": buildinfo.BuiltAt, "state_schema": s.store.Schema(), "operations_schema": operations.SchemaVersion})
}

type loginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	opID := operationID(r)
	if !validOrigin(r) {
		s.auditEvent(r, "", "", "auth.login", "", "denied", "origin_rejected")
		writeError(w, http.StatusForbidden, "origin_rejected", "Request origin is not allowed", opID)
		return
	}
	var in loginRequest
	if err := decodeJSON(r, &in); err != nil {
		s.auditEvent(r, "", "", "auth.login", "", "failed", "invalid_request")
		writeError(w, http.StatusBadRequest, "invalid_request", "Invalid JSON request", opID)
		return
	}
	target := strings.ToLower(strings.TrimSpace(in.Username))
	key := clientIP(r) + "|" + target
	if !s.limiter.Allowed(key) {
		s.auditEvent(r, "", "", "auth.login", target, "denied", "auth_rate_limited")
		writeError(w, http.StatusTooManyRequests, "auth_rate_limited", "Too many authentication attempts", opID)
		return
	}
	u, ok := s.store.VerifyCredentials(in.Username, in.Password)
	if !ok {
		s.limiter.Failure(key)
		s.auditEvent(r, "", "", "auth.login", target, "failed", "invalid_credentials")
		writeError(w, http.StatusUnauthorized, "invalid_credentials", "Invalid username or password", opID)
		return
	}
	s.limiter.Success(key)
	token, session, err := s.sessions.Create(u)
	if err != nil {
		s.auditEvent(r, u.Username, string(u.Role), "auth.login", u.Username, "failed", "session_create_failed")
		writeError(w, http.StatusInternalServerError, "session_create_failed", "Unable to create session", opID)
		return
	}
	setSessionCookie(w, token, int((12 * time.Hour).Seconds()))
	s.auditEvent(r, u.Username, string(u.Role), "auth.login", u.Username, "success", "")
	writeJSON(w, http.StatusOK, envelope{"user": publicUser(u), "csrf_token": session.CSRF})
}

func (s *Server) session(w http.ResponseWriter, r *http.Request) {
	sess, u, ok := s.currentSession(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "authentication_required", "Authentication required", operationID(r))
		return
	}
	writeJSON(w, http.StatusOK, envelope{"user": publicUser(u), "csrf_token": sess.CSRF})
}

func (s *Server) logout(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	if !validMutation(r, sess) {
		s.auditEvent(r, u.Username, string(u.Role), "auth.logout", u.Username, "denied", "csrf_rejected")
		writeError(w, http.StatusForbidden, "csrf_rejected", "CSRF or origin validation failed", operationID(r))
		return
	}
	if c, err := r.Cookie("cc_session"); err == nil {
		s.sessions.Revoke(c.Value)
	}
	clearSessionCookie(w)
	s.auditEvent(r, u.Username, string(u.Role), "auth.logout", u.Username, "success", "")
	writeJSON(w, http.StatusOK, envelope{"status": "logged_out"})
}

type changePasswordRequest struct {
	CurrentPassword string `json:"current_password"`
	NewPassword     string `json:"new_password"`
}

func (s *Server) changePassword(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	if !validMutation(r, sess) {
		s.auditEvent(r, u.Username, string(u.Role), "auth.password.change", u.Username, "denied", "csrf_rejected")
		writeError(w, http.StatusForbidden, "csrf_rejected", "CSRF or origin validation failed", operationID(r))
		return
	}
	var in changePasswordRequest
	if err := decodeJSON(r, &in); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "Invalid JSON request", operationID(r))
		return
	}
	if !s.beginOperation(w, r, u, "auth.password.change", u.Username) {
		return
	}
	if err := s.store.ChangePassword(u.Username, in.CurrentPassword, in.NewPassword); err != nil {
		s.finishOperation(r, u, "auth.password.change", u.Username, operations.StatusFailed, "password_change_failed")
		writeError(w, http.StatusBadRequest, "password_change_failed", err.Error(), operationID(r))
		return
	}
	s.sessions.RevokeUser(u.Username)
	clearSessionCookie(w)
	s.finishOperation(r, u, "auth.password.change", u.Username, operations.StatusSucceeded, "")
	writeJSON(w, http.StatusOK, envelope{"status": "password_changed", "reauthentication_required": true})
}

func (s *Server) systemStatus(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	ready, detail := s.store.Ready()
	now := time.Now().UTC()
	writeJSON(w, http.StatusOK, envelope{"user": publicUser(u), "status": "ok", "ready": ready, "readiness_detail": detail, "state_schema": s.store.Schema(), "operations_schema": operations.SchemaVersion, "service": envelope{"name": "control-center", "state": "running", "pid": os.Getpid(), "started_at": s.startedAt, "uptime_seconds": now.Sub(s.startedAt).Seconds()}, "runtime": envelope{"go_version": runtime.Version(), "goos": runtime.GOOS, "goarch": runtime.GOARCH, "goroutines": runtime.NumGoroutine()}, "operation_count": s.operations.Count()})
}

func (s *Server) networkInterfaces(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	interfaces, err := networkmodel.Inventory()
	if err != nil {
		s.auditEvent(r, u.Username, string(u.Role), "network.interfaces.read", "host", "failed", "network_inventory_unavailable")
		writeError(w, http.StatusServiceUnavailable, "network_inventory_unavailable", "Network interface inventory is unavailable", operationID(r))
		return
	}
	s.auditEvent(r, u.Username, string(u.Role), "network.interfaces.read", "host", "success", "")
	writeJSON(w, http.StatusOK, envelope{"interfaces": interfaces, "count": len(interfaces), "observed_at": time.Now().UTC().Format(time.RFC3339)})
}

func (s *Server) listUsers(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	users := s.store.ListUsers()
	out := make([]any, 0, len(users))
	for _, item := range users {
		out = append(out, publicUser(item))
	}
	writeJSON(w, http.StatusOK, envelope{"users": out})
}

type createUserRequest struct {
	Username string     `json:"username"`
	Password string     `json:"password"`
	Role     state.Role `json:"role"`
}

func (s *Server) createUser(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	if !validMutation(r, sess) {
		s.auditEvent(r, u.Username, string(u.Role), "rbac.user.create", "", "denied", "csrf_rejected")
		writeError(w, http.StatusForbidden, "csrf_rejected", "CSRF or origin validation failed", operationID(r))
		return
	}
	var in createUserRequest
	if err := decodeJSON(r, &in); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "Invalid JSON request", operationID(r))
		return
	}
	target := strings.ToLower(strings.TrimSpace(in.Username))
	if !s.beginOperation(w, r, u, "rbac.user.create", target) {
		return
	}
	created, err := s.store.CreateUser(in.Username, in.Password, in.Role)
	if err != nil {
		s.finishOperation(r, u, "rbac.user.create", target, operations.StatusFailed, "user_create_failed")
		writeError(w, http.StatusBadRequest, "user_create_failed", err.Error(), operationID(r))
		return
	}
	s.finishOperation(r, u, "rbac.user.create", created.Username, operations.StatusSucceeded, "")
	writeJSON(w, http.StatusCreated, envelope{"user": publicUser(created)})
}

type blockRequest struct {
	Blocked bool `json:"blocked"`
}

func (s *Server) setBlocked(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	if !validMutation(r, sess) {
		s.auditEvent(r, u.Username, string(u.Role), "rbac.user.block", r.PathValue("username"), "denied", "csrf_rejected")
		writeError(w, http.StatusForbidden, "csrf_rejected", "CSRF or origin validation failed", operationID(r))
		return
	}
	target := r.PathValue("username")
	if strings.EqualFold(target, u.Username) {
		writeError(w, http.StatusConflict, "self_block_forbidden", "Current user cannot block itself", operationID(r))
		return
	}
	var in blockRequest
	if err := decodeJSON(r, &in); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "Invalid JSON request", operationID(r))
		return
	}
	kind := "rbac.user.unblock"
	if in.Blocked {
		kind = "rbac.user.block"
	}
	if !s.beginOperation(w, r, u, kind, target) {
		return
	}
	updated, err := s.store.SetBlocked(target, in.Blocked)
	if err != nil {
		s.finishOperation(r, u, kind, target, operations.StatusFailed, "user_block_failed")
		writeError(w, http.StatusConflict, "user_block_failed", err.Error(), operationID(r))
		return
	}
	if in.Blocked {
		s.sessions.RevokeUser(updated.Username)
	}
	s.finishOperation(r, u, kind, updated.Username, operations.StatusSucceeded, "")
	writeJSON(w, http.StatusOK, envelope{"user": publicUser(updated)})
}

func (s *Server) listOperations(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	writeJSON(w, http.StatusOK, envelope{"operations": s.operations.List(queryLimit(r, 100))})
}
func (s *Server) listAudit(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	events, err := s.audit.Recent(queryLimit(r, 100))
	if err != nil {
		writeError(w, http.StatusServiceUnavailable, "audit_unavailable", "Audit log is unavailable", operationID(r))
		return
	}
	writeJSON(w, http.StatusOK, envelope{"events": events})
}
func (s *Server) diagnosticsSummary(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	ready, detail := s.store.Ready()
	auditEvents, err := s.audit.Recent(1)
	auditOK := err == nil
	writeJSON(w, http.StatusOK, envelope{"product": "Control Center", "version": buildinfo.Version, "ready": ready, "readiness_detail": detail, "state_schema": s.store.Schema(), "operation_count": s.operations.Count(), "audit_readable": auditOK, "audit_has_events": len(auditEvents) > 0, "started_at": s.startedAt, "uptime_seconds": time.Since(s.startedAt).Seconds()})
}
func (s *Server) diagnosticsExport(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	bundle, err := diagnostics.Build(s.startedAt, operationID(r), s.store, s.audit, s.operations)
	if err != nil {
		s.auditEvent(r, u.Username, string(u.Role), "diagnostics.export", "control-center", "failed", "diagnostics_build_failed")
		writeError(w, http.StatusServiceUnavailable, "diagnostics_build_failed", "Unable to build diagnostic package", operationID(r))
		return
	}
	s.auditEvent(r, u.Username, string(u.Role), "diagnostics.export", "control-center", "success", "")
	name := fmt.Sprintf("control-center-diagnostics-%s.tar.gz", time.Now().UTC().Format("20060102T150405Z"))
	w.Header().Set("Content-Type", "application/gzip")
	w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=%q", name))
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(bundle)
}

func (s *Server) beginOperation(w http.ResponseWriter, r *http.Request, u state.User, kind, target string) bool {
	_, err := s.operations.Start(operationID(r), kind, u.Username, string(u.Role), target)
	if err != nil {
		s.logger.Error("operation start failed", "operation_id", operationID(r), "kind", kind, "error", err)
		writeError(w, http.StatusServiceUnavailable, "operation_store_unavailable", "Operation tracking is unavailable", operationID(r))
		return false
	}
	return true
}
func (s *Server) finishOperation(r *http.Request, u state.User, kind, target string, status operations.Status, errorCode string) {
	if _, err := s.operations.Finish(operationID(r), status, errorCode); err != nil {
		s.logger.Error("operation finish failed", "operation_id", operationID(r), "kind", kind, "error", err)
	}
	result := "success"
	if status != operations.StatusSucceeded {
		result = "failed"
	}
	s.auditEvent(r, u.Username, string(u.Role), kind, target, result, errorCode)
}
func (s *Server) auditEvent(r *http.Request, actor, role, action, target, result, errorCode string) {
	if s.audit == nil {
		return
	}
	if err := s.audit.Append(observability.AuditEvent{OperationID: operationID(r), Actor: actor, Role: role, Action: action, Target: target, Result: result, RemoteIP: clientIP(r), ErrorCode: errorCode}); err != nil {
		s.logger.Error("audit append failed", "operation_id", operationID(r), "action", action, "error", err)
	}
}

func (s *Server) requireAuth(next func(http.ResponseWriter, *http.Request, auth.Session, state.User)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sess, u, ok := s.currentSession(r)
		if !ok {
			writeError(w, http.StatusUnauthorized, "authentication_required", "Authentication required", operationID(r))
			return
		}
		next(w, r, sess, u)
	}
}
func (s *Server) requirePermission(permission string, next func(http.ResponseWriter, *http.Request, auth.Session, state.User)) http.HandlerFunc {
	return s.requireAuth(func(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
		if !hasPermission(u.Role, permission) {
			writeError(w, http.StatusForbidden, "permission_denied", "Permission denied", operationID(r))
			return
		}
		next(w, r, sess, u)
	})
}
func (s *Server) currentSession(r *http.Request) (auth.Session, state.User, bool) {
	cookie, err := r.Cookie("cc_session")
	if err != nil {
		return auth.Session{}, state.User{}, false
	}
	sess, ok := s.sessions.Lookup(cookie.Value)
	if !ok {
		return auth.Session{}, state.User{}, false
	}
	u, ok := s.store.GetUser(sess.Username)
	if !ok || u.Blocked || u.Role != sess.Role {
		s.sessions.Revoke(cookie.Value)
		return auth.Session{}, state.User{}, false
	}
	return sess, u, true
}
func hasPermission(role state.Role, permission string) bool {
	if role == state.RoleAdmin {
		return true
	}
	if role == state.RoleViewer {
		return permission == "system.read"
	}
	return false
}
func publicUser(u state.User) envelope {
	return envelope{"username": u.Username, "role": u.Role, "blocked": u.Blocked, "must_change_password": u.MustChangePassword, "created_at": u.CreatedAt, "password_changed_at": u.PasswordChangedAt}
}
func validMutation(r *http.Request, sess auth.Session) bool {
	if !validOrigin(r) {
		return false
	}
	return strings.TrimSpace(r.Header.Get("X-CSRF-Token")) != "" && r.Header.Get("X-CSRF-Token") == sess.CSRF
}
func validOrigin(r *http.Request) bool {
	origin := strings.TrimSpace(r.Header.Get("Origin"))
	if origin == "" {
		return true
	}
	u, err := url.Parse(origin)
	if err != nil || u.Host == "" {
		return false
	}
	return strings.EqualFold(u.Host, r.Host) && (u.Scheme == "https" || u.Scheme == "http")
}
func clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil {
		return host
	}
	return r.RemoteAddr
}
func queryLimit(r *http.Request, fallback int) int {
	raw := r.URL.Query().Get("limit")
	if raw == "" {
		return fallback
	}
	n, err := strconv.Atoi(raw)
	if err != nil || n < 1 {
		return fallback
	}
	if n > 500 {
		return 500
	}
	return n
}
func setSessionCookie(w http.ResponseWriter, token string, maxAge int) {
	http.SetCookie(w, &http.Cookie{Name: "cc_session", Value: token, Path: "/", HttpOnly: true, Secure: true, SameSite: http.SameSiteStrictMode, MaxAge: maxAge})
}
func clearSessionCookie(w http.ResponseWriter) {
	http.SetCookie(w, &http.Cookie{Name: "cc_session", Value: "", Path: "/", HttpOnly: true, Secure: true, SameSite: http.SameSiteStrictMode, MaxAge: -1})
}
func decodeJSON(r *http.Request, out any) error {
	defer r.Body.Close()
	dec := json.NewDecoder(io.LimitReader(r.Body, 64<<10))
	dec.DisallowUnknownFields()
	if err := dec.Decode(out); err != nil {
		return err
	}
	var extra any
	if err := dec.Decode(&extra); !errors.Is(err, io.EOF) {
		return errors.New("request must contain a single JSON value")
	}
	return nil
}
func requestMiddleware(logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		opID := newOperationID()
		r.Header.Set("X-Control-Center-Operation-ID", opID)
		w.Header().Set("X-Control-Center-Operation-ID", opID)
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
		w.Header().Set("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'")
		start := time.Now()
		next.ServeHTTP(w, r)
		logger.Info("http request", "method", r.Method, "path", r.URL.Path, "operation_id", opID, "duration_ms", time.Since(start).Milliseconds())
	})
}
func operationID(r *http.Request) string {
	if v := strings.TrimSpace(r.Header.Get("X-Control-Center-Operation-ID")); v != "" {
		return v
	}
	return "unknown"
}
func newOperationID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return time.Now().UTC().Format("20060102T150405.000000000")
	}
	return hex.EncodeToString(b[:])
}
func writeJSON(w http.ResponseWriter, status int, body envelope) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}
func writeError(w http.ResponseWriter, status int, code, message, opID string) {
	writeJSON(w, status, envelope{"error": envelope{"code": code, "message": message, "operation_id": opID}})
}
