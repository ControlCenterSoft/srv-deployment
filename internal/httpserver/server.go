package httpserver

import (
	"crypto/rand"
	"embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"io/fs"
	"log/slog"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/ControlCenterSoft/srv-deployment/internal/auth"
	"github.com/ControlCenterSoft/srv-deployment/internal/buildinfo"
	"github.com/ControlCenterSoft/srv-deployment/internal/state"
)

//go:embed web/*
var webFS embed.FS

type envelope map[string]any

type Server struct {
	logger   *slog.Logger
	store    *state.Store
	sessions *auth.Manager
	limiter  *auth.LoginLimiter
}

func New(logger *slog.Logger, store *state.Store) http.Handler {
	s := &Server{
		logger:   logger,
		store:    store,
		sessions: auth.NewManager(12 * time.Hour),
		limiter:  auth.NewLoginLimiter(5, 5*time.Minute),
	}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v1/health", s.health)
	mux.HandleFunc("GET /api/v1/readiness", s.readiness)
	mux.HandleFunc("GET /api/v1/version", s.version)
	mux.HandleFunc("POST /api/v1/auth/login", s.login)
	mux.HandleFunc("GET /api/v1/auth/session", s.session)
	mux.HandleFunc("POST /api/v1/auth/logout", s.requireAuth(s.logout))
	mux.HandleFunc("POST /api/v1/auth/password", s.requireAuth(s.changePassword))
	mux.HandleFunc("GET /api/v1/system/status", s.requireAuth(s.systemStatus))
	mux.HandleFunc("GET /api/v1/rbac/users", s.requirePermission("rbac.users.read", s.listUsers))
	mux.HandleFunc("POST /api/v1/rbac/users", s.requirePermission("rbac.users.write", s.createUser))
	mux.HandleFunc("POST /api/v1/rbac/users/{username}/blocked", s.requirePermission("rbac.users.write", s.setBlocked))
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
	writeJSON(w, status, envelope{"status": detail, "ready": ready, "checks": []any{envelope{"name": "active_admin", "ok": ready}}})
}

func (s *Server) version(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, envelope{"product": "Control Center", "version": buildinfo.Version, "commit": buildinfo.Commit, "built_at": buildinfo.BuiltAt, "state_schema": s.store.Schema()})
}

type loginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	if !validOrigin(r) {
		writeError(w, http.StatusForbidden, "origin_rejected", "Request origin is not allowed", operationID(r))
		return
	}
	var in loginRequest
	if err := decodeJSON(r, &in); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "Invalid JSON request", operationID(r))
		return
	}
	key := clientIP(r) + "|" + strings.ToLower(strings.TrimSpace(in.Username))
	if !s.limiter.Allowed(key) {
		writeError(w, http.StatusTooManyRequests, "auth_rate_limited", "Too many authentication attempts", operationID(r))
		return
	}
	u, ok := s.store.VerifyCredentials(in.Username, in.Password)
	if !ok {
		s.limiter.Failure(key)
		writeError(w, http.StatusUnauthorized, "invalid_credentials", "Invalid username or password", operationID(r))
		return
	}
	s.limiter.Success(key)
	token, session, err := s.sessions.Create(u)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "session_create_failed", "Unable to create session", operationID(r))
		return
	}
	setSessionCookie(w, token, int((12 * time.Hour).Seconds()))
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
		writeError(w, http.StatusForbidden, "csrf_rejected", "CSRF or origin validation failed", operationID(r))
		return
	}
	if c, err := r.Cookie("cc_session"); err == nil {
		s.sessions.Revoke(c.Value)
	}
	clearSessionCookie(w)
	writeJSON(w, http.StatusOK, envelope{"status": "logged_out"})
}

type changePasswordRequest struct {
	CurrentPassword string `json:"current_password"`
	NewPassword     string `json:"new_password"`
}

func (s *Server) changePassword(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	if !validMutation(r, sess) {
		writeError(w, http.StatusForbidden, "csrf_rejected", "CSRF or origin validation failed", operationID(r))
		return
	}
	var in changePasswordRequest
	if err := decodeJSON(r, &in); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "Invalid JSON request", operationID(r))
		return
	}
	if err := s.store.ChangePassword(u.Username, in.CurrentPassword, in.NewPassword); err != nil {
		writeError(w, http.StatusBadRequest, "password_change_failed", err.Error(), operationID(r))
		return
	}
	s.sessions.RevokeUser(u.Username)
	clearSessionCookie(w)
	writeJSON(w, http.StatusOK, envelope{"status": "password_changed", "reauthentication_required": true})
}

func (s *Server) systemStatus(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	writeJSON(w, http.StatusOK, envelope{"user": publicUser(u), "state_schema": s.store.Schema(), "status": "ok"})
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
		writeError(w, http.StatusForbidden, "csrf_rejected", "CSRF or origin validation failed", operationID(r))
		return
	}
	var in createUserRequest
	if err := decodeJSON(r, &in); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "Invalid JSON request", operationID(r))
		return
	}
	created, err := s.store.CreateUser(in.Username, in.Password, in.Role)
	if err != nil {
		writeError(w, http.StatusBadRequest, "user_create_failed", err.Error(), operationID(r))
		return
	}
	writeJSON(w, http.StatusCreated, envelope{"user": publicUser(created)})
}

type blockRequest struct {
	Blocked bool `json:"blocked"`
}

func (s *Server) setBlocked(w http.ResponseWriter, r *http.Request, sess auth.Session, u state.User) {
	if !validMutation(r, sess) {
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
	updated, err := s.store.SetBlocked(target, in.Blocked)
	if err != nil {
		writeError(w, http.StatusConflict, "user_block_failed", err.Error(), operationID(r))
		return
	}
	if in.Blocked {
		s.sessions.RevokeUser(updated.Username)
	}
	writeJSON(w, http.StatusOK, envelope{"user": publicUser(updated)})
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
