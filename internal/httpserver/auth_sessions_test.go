package httpserver

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestRevokeOtherSessionsIsSelfScopedCSRFAuditedOperation(t *testing.T) {
	app := newTestApp(t)
	oldCookie, _ := login(t, app, "admin", app.adminPassword)
	currentCookie, currentCSRF := login(t, app, "admin", app.adminPassword)

	anonymous := requestJSON(t, app.handler, http.MethodPost, "/api/v1/auth/sessions/revoke-others", `{}`, nil, "")
	if anonymous.Code != http.StatusUnauthorized {
		t.Fatalf("anonymous status=%d body=%s", anonymous.Code, anonymous.Body.String())
	}

	missingCSRF := requestJSON(t, app.handler, http.MethodPost, "/api/v1/auth/sessions/revoke-others", `{}`, currentCookie, "")
	if missingCSRF.Code != http.StatusForbidden {
		t.Fatalf("missing csrf status=%d body=%s", missingCSRF.Code, missingCSRF.Body.String())
	}
	if rr := requestJSON(t, app.handler, http.MethodGet, "/api/v1/auth/session", "", oldCookie, ""); rr.Code != http.StatusOK {
		t.Fatalf("missing csrf revoked old session: status=%d body=%s", rr.Code, rr.Body.String())
	}

	foreignOriginReq := httptest.NewRequest(http.MethodPost, "/api/v1/auth/sessions/revoke-others", strings.NewReader(`{}`))
	foreignOriginReq.Header.Set("Content-Type", "application/json")
	foreignOriginReq.Header.Set("X-CSRF-Token", currentCSRF)
	foreignOriginReq.Header.Set("Origin", "https://untrusted.example.invalid")
	foreignOriginReq.AddCookie(currentCookie)
	foreignOrigin := httptest.NewRecorder()
	app.handler.ServeHTTP(foreignOrigin, foreignOriginReq)
	if foreignOrigin.Code != http.StatusForbidden {
		t.Fatalf("foreign origin status=%d body=%s", foreignOrigin.Code, foreignOrigin.Body.String())
	}
	if rr := requestJSON(t, app.handler, http.MethodGet, "/api/v1/auth/session", "", oldCookie, ""); rr.Code != http.StatusOK {
		t.Fatalf("foreign origin revoked old session: status=%d body=%s", rr.Code, rr.Body.String())
	}

	selectorInjection := requestJSON(t, app.handler, http.MethodPost, "/api/v1/auth/sessions/revoke-others", `{"username":"someone-else"}`, currentCookie, currentCSRF)
	if selectorInjection.Code != http.StatusBadRequest {
		t.Fatalf("selector injection status=%d body=%s", selectorInjection.Code, selectorInjection.Body.String())
	}
	if rr := requestJSON(t, app.handler, http.MethodGet, "/api/v1/auth/session", "", oldCookie, ""); rr.Code != http.StatusOK {
		t.Fatalf("selector injection revoked old session: status=%d body=%s", rr.Code, rr.Body.String())
	}

	success := requestJSON(t, app.handler, http.MethodPost, "/api/v1/auth/sessions/revoke-others", `{}`, currentCookie, currentCSRF)
	if success.Code != http.StatusOK {
		t.Fatalf("success status=%d body=%s", success.Code, success.Body.String())
	}
	var result struct {
		Status       string `json:"status"`
		RevokedCount int    `json:"revoked_count"`
	}
	if err := json.Unmarshal(success.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	if result.Status != "other_sessions_revoked" || result.RevokedCount != 1 {
		t.Fatalf("unexpected result: %+v", result)
	}

	if rr := requestJSON(t, app.handler, http.MethodGet, "/api/v1/auth/session", "", currentCookie, ""); rr.Code != http.StatusOK {
		t.Fatalf("current session revoked: status=%d body=%s", rr.Code, rr.Body.String())
	}
	if rr := requestJSON(t, app.handler, http.MethodGet, "/api/v1/auth/session", "", oldCookie, ""); rr.Code != http.StatusUnauthorized {
		t.Fatalf("old session status=%d body=%s", rr.Code, rr.Body.String())
	}

	operations := requestJSON(t, app.handler, http.MethodGet, "/api/v1/operations", "", currentCookie, "")
	if operations.Code != http.StatusOK || !strings.Contains(operations.Body.String(), `"kind":"`+revokeOtherSessionsAction+`"`) || !strings.Contains(operations.Body.String(), `"status":"succeeded"`) {
		t.Fatalf("operation evidence missing: status=%d body=%s", operations.Code, operations.Body.String())
	}
	audit := requestJSON(t, app.handler, http.MethodGet, "/api/v1/audit", "", currentCookie, "")
	if audit.Code != http.StatusOK || !strings.Contains(audit.Body.String(), `"action":"`+revokeOtherSessionsAction+`"`) || !strings.Contains(audit.Body.String(), `"result":"success"`) || !strings.Contains(audit.Body.String(), `"error_code":"invalid_request"`) {
		t.Fatalf("audit evidence missing: status=%d body=%s", audit.Code, audit.Body.String())
	}
}
