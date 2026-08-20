package httpserver

import (
	"bytes"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/ControlCenterSoft/srv-deployment/internal/observability"
	"github.com/ControlCenterSoft/srv-deployment/internal/operations"
	"github.com/ControlCenterSoft/srv-deployment/internal/state"
)

type testApp struct {
	handler       http.Handler
	store         *state.Store
	adminPassword string
}

func newTestApp(t *testing.T) testApp {
	t.Helper()
	root := t.TempDir()
	store, err := state.Open(root + "/state")
	if err != nil {
		t.Fatal(err)
	}
	opStore, err := operations.Open(root + "/state")
	if err != nil {
		t.Fatal(err)
	}
	audit, err := observability.OpenAudit(root + "/log")
	if err != nil {
		t.Fatal(err)
	}
	password, created, err := store.BootstrapAdmin("admin")
	if err != nil || !created {
		t.Fatalf("bootstrap created=%v err=%v", created, err)
	}
	return testApp{handler: New(slog.New(slog.NewTextHandler(io.Discard, nil)), store, opStore, audit), store: store, adminPassword: password}
}

func requestJSON(t *testing.T, h http.Handler, method, path, body string, cookie *http.Cookie, csrf string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	if cookie != nil {
		req.AddCookie(cookie)
	}
	if csrf != "" {
		req.Header.Set("X-CSRF-Token", csrf)
	}
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, req)
	return rr
}

func login(t *testing.T, app testApp, username, password string) (*http.Cookie, string) {
	t.Helper()
	payload, _ := json.Marshal(map[string]string{"username": username, "password": password})
	rr := requestJSON(t, app.handler, http.MethodPost, "/api/v1/auth/login", string(payload), nil, "")
	if rr.Code != http.StatusOK {
		t.Fatalf("login status=%d body=%s", rr.Code, rr.Body.String())
	}
	res := rr.Result()
	defer res.Body.Close()
	var cookie *http.Cookie
	for _, c := range res.Cookies() {
		if c.Name == "cc_session" {
			cookie = c
		}
	}
	if cookie == nil {
		t.Fatal("missing session cookie")
	}
	var body struct {
		CSRF string `json:"csrf_token"`
	}
	if err := json.NewDecoder(bytes.NewReader(rr.Body.Bytes())).Decode(&body); err != nil {
		t.Fatal(err)
	}
	if body.CSRF == "" {
		t.Fatal("missing csrf token")
	}
	return cookie, body.CSRF
}

func TestHealthReadinessAndVersion(t *testing.T) {
	app := newTestApp(t)
	for _, path := range []string{"/api/v1/health", "/api/v1/readiness", "/api/v1/version"} {
		req := httptest.NewRequest(http.MethodGet, path, nil)
		rr := httptest.NewRecorder()
		app.handler.ServeHTTP(rr, req)
		if rr.Code != http.StatusOK {
			t.Fatalf("%s status=%d", path, rr.Code)
		}
		if rr.Header().Get("X-Control-Center-Operation-ID") == "" {
			t.Fatal("missing operation id")
		}
	}
}

func TestLoginCookieSecurityAndSession(t *testing.T) {
	app := newTestApp(t)
	cookie, csrf := login(t, app, "admin", app.adminPassword)
	if !cookie.HttpOnly || !cookie.Secure || cookie.SameSite != http.SameSiteStrictMode || cookie.Path != "/" {
		t.Fatalf("insecure cookie: %+v", cookie)
	}
	rr := requestJSON(t, app.handler, http.MethodGet, "/api/v1/auth/session", "", cookie, "")
	if rr.Code != http.StatusOK || csrf == "" {
		t.Fatalf("session status=%d body=%s", rr.Code, rr.Body.String())
	}
}

func TestAuthenticationAndCSRFAreServerSide(t *testing.T) {
	app := newTestApp(t)
	rr := requestJSON(t, app.handler, http.MethodGet, "/api/v1/rbac/users", "", nil, "")
	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("anonymous status=%d", rr.Code)
	}
	cookie, _ := login(t, app, "admin", app.adminPassword)
	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/rbac/users", `{"username":"viewer","password":"viewer-password-123","role":"viewer"}`, cookie, "")
	if rr.Code != http.StatusForbidden {
		t.Fatalf("missing csrf status=%d body=%s", rr.Code, rr.Body.String())
	}
}

func TestViewerCannotPerformPrivilegedOperation(t *testing.T) {
	app := newTestApp(t)
	adminCookie, adminCSRF := login(t, app, "admin", app.adminPassword)
	rr := requestJSON(t, app.handler, http.MethodPost, "/api/v1/rbac/users", `{"username":"viewer","password":"viewer-password-123","role":"viewer"}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusCreated {
		t.Fatalf("create viewer status=%d body=%s", rr.Code, rr.Body.String())
	}
	viewerCookie, viewerCSRF := login(t, app, "viewer", "viewer-password-123")
	rr = requestJSON(t, app.handler, http.MethodGet, "/api/v1/system/status", "", viewerCookie, "")
	if rr.Code != http.StatusOK {
		t.Fatalf("viewer read status=%d", rr.Code)
	}
	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/rbac/users", `{"username":"blocked","password":"blocked-password-123","role":"viewer"}`, viewerCookie, viewerCSRF)
	if rr.Code != http.StatusForbidden {
		t.Fatalf("viewer write status=%d body=%s", rr.Code, rr.Body.String())
	}
	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/rbac/users/viewer/blocked", `{"blocked":true}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusOK {
		t.Fatalf("block viewer status=%d body=%s", rr.Code, rr.Body.String())
	}
	rr = requestJSON(t, app.handler, http.MethodGet, "/api/v1/system/status", "", viewerCookie, "")
	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("blocked viewer session status=%d", rr.Code)
	}
}

func TestLoginRateLimit(t *testing.T) {
	app := newTestApp(t)
	for i := 0; i < 5; i++ {
		rr := requestJSON(t, app.handler, http.MethodPost, "/api/v1/auth/login", `{"username":"ghost","password":"wrong-password-123"}`, nil, "")
		if rr.Code != http.StatusUnauthorized {
			t.Fatalf("attempt %d status=%d body=%s", i+1, rr.Code, rr.Body.String())
		}
	}
	rr := requestJSON(t, app.handler, http.MethodPost, "/api/v1/auth/login", `{"username":"ghost","password":"wrong-password-123"}`, nil, "")
	if rr.Code != http.StatusTooManyRequests {
		t.Fatalf("rate limit status=%d body=%s", rr.Code, rr.Body.String())
	}
}

func TestPasswordChangeRevokesSessions(t *testing.T) {
	app := newTestApp(t)
	cookie, csrf := login(t, app, "admin", app.adminPassword)
	payload, _ := json.Marshal(map[string]string{"current_password": app.adminPassword, "new_password": "new-admin-password-123"})
	rr := requestJSON(t, app.handler, http.MethodPost, "/api/v1/auth/password", string(payload), cookie, csrf)
	if rr.Code != http.StatusOK {
		t.Fatalf("password change status=%d body=%s", rr.Code, rr.Body.String())
	}
	rr = requestJSON(t, app.handler, http.MethodGet, "/api/v1/auth/session", "", cookie, "")
	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("old session status=%d", rr.Code)
	}
	_, _ = login(t, app, "admin", "new-admin-password-123")
}

func TestAPINotFoundUsesMachineReadableError(t *testing.T) {
	app := newTestApp(t)
	req := httptest.NewRequest(http.MethodGet, "/api/v1/missing", nil)
	rr := httptest.NewRecorder()
	app.handler.ServeHTTP(rr, req)
	if rr.Code != http.StatusNotFound {
		t.Fatalf("status=%d", rr.Code)
	}
	var body struct {
		Error struct {
			Code string `json:"code"`
		} `json:"error"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.Error.Code != "api_not_found" {
		t.Fatalf("code=%q", body.Error.Code)
	}
}

func TestWebUIServed(t *testing.T) {
	app := newTestApp(t)
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	rr := httptest.NewRecorder()
	app.handler.ServeHTTP(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("status=%d", rr.Code)
	}
}

func TestOperationAuditAndDiagnosticsEndpoints(t *testing.T) {
	app := newTestApp(t)
	adminCookie, adminCSRF := login(t, app, "admin", app.adminPassword)
	rr := requestJSON(t, app.handler, http.MethodPost, "/api/v1/rbac/users", `{"username":"viewer2","password":"viewer2-password-123","role":"viewer"}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusCreated {
		t.Fatalf("create viewer status=%d body=%s", rr.Code, rr.Body.String())
	}
	for _, path := range []string{"/api/v1/operations", "/api/v1/audit", "/api/v1/diagnostics/summary"} {
		rr = requestJSON(t, app.handler, http.MethodGet, path, "", adminCookie, "")
		if rr.Code != http.StatusOK {
			t.Fatalf("%s status=%d body=%s", path, rr.Code, rr.Body.String())
		}
	}
	rr = requestJSON(t, app.handler, http.MethodGet, "/api/v1/diagnostics/export", "", adminCookie, "")
	if rr.Code != http.StatusOK {
		t.Fatalf("diagnostics export status=%d body=%s", rr.Code, rr.Body.String())
	}
	if rr.Header().Get("Content-Type") != "application/gzip" || rr.Body.Len() == 0 {
		t.Fatalf("invalid diagnostics response headers=%v size=%d", rr.Header(), rr.Body.Len())
	}
}

func TestViewerCannotReadAuditOrOperations(t *testing.T) {
	app := newTestApp(t)
	adminCookie, adminCSRF := login(t, app, "admin", app.adminPassword)
	rr := requestJSON(t, app.handler, http.MethodPost, "/api/v1/rbac/users", `{"username":"viewer3","password":"viewer3-password-123","role":"viewer"}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusCreated {
		t.Fatalf("create viewer status=%d", rr.Code)
	}
	viewerCookie, _ := login(t, app, "viewer3", "viewer3-password-123")
	for _, path := range []string{"/api/v1/operations", "/api/v1/audit", "/api/v1/diagnostics/export"} {
		rr = requestJSON(t, app.handler, http.MethodGet, path, "", viewerCookie, "")
		if rr.Code != http.StatusForbidden {
			t.Fatalf("viewer %s status=%d", path, rr.Code)
		}
	}
	rr = requestJSON(t, app.handler, http.MethodGet, "/api/v1/diagnostics/summary", "", viewerCookie, "")
	if rr.Code != http.StatusOK {
		t.Fatalf("viewer diagnostics summary status=%d", rr.Code)
	}
}
