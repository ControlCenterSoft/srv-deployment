package httpserver

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestFleetDisconnectRevokesAgentCredentialAndIsIdempotent(t *testing.T) {
	app := newTestApp(t)
	adminCookie, adminCSRF := login(t, app, "admin", app.adminPassword)

	rr := requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/nodes", `{"name":"srv-01","address":"10.10.0.11"}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusCreated {
		t.Fatalf("create=%d %s", rr.Code, rr.Body.String())
	}
	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/nodes/srv-01/enrollment", `{}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusCreated {
		t.Fatalf("prepare=%d %s", rr.Code, rr.Body.String())
	}
	var prepared struct {
		Enrollment struct {
			Token string `json:"token"`
		} `json:"enrollment"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &prepared); err != nil {
		t.Fatal(err)
	}

	enrollBody := `{"node_id":"srv-01","token":"` + prepared.Enrollment.Token + `","agent_version":"1.1.9"}`
	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/enroll", enrollBody, nil, "")
	if rr.Code != http.StatusOK {
		t.Fatalf("enroll=%d %s", rr.Code, rr.Body.String())
	}
	var enrolled struct {
		AgentCredential string `json:"agent_credential"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &enrolled); err != nil {
		t.Fatal(err)
	}
	if enrolled.AgentCredential == "" {
		t.Fatal("missing agent credential")
	}

	heartbeat := `{"node_id":"srv-01","agent_version":"1.1.9","hostname":"srv-01.example","os_name":"Ubuntu","os_version":"26.04","architecture":"amd64"}`
	sendHeartbeat := func(credential string) *httptest.ResponseRecorder {
		t.Helper()
		req := httptest.NewRequest(http.MethodPost, "/api/v1/fleet/heartbeat", strings.NewReader(heartbeat))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", "Bearer "+credential)
		out := httptest.NewRecorder()
		app.handler.ServeHTTP(out, req)
		return out
	}
	if got := sendHeartbeat(enrolled.AgentCredential); got.Code != http.StatusOK {
		t.Fatalf("heartbeat before disconnect=%d %s", got.Code, got.Body.String())
	}

	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/nodes/srv-01/disconnect", `{}`, adminCookie, "")
	if rr.Code != http.StatusForbidden {
		t.Fatalf("disconnect without csrf=%d %s", rr.Code, rr.Body.String())
	}

	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/nodes/srv-01/disconnect", `{}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusOK {
		t.Fatalf("disconnect=%d %s", rr.Code, rr.Body.String())
	}
	for _, want := range []string{
		`"status":"pending_enrollment"`,
		`"disconnected":true`,
		`"agent_credential_revoked":true`,
		`"enrollment_token_revoked":true`,
		`"re_enrollment_required":true`,
		`"remote_host_changed":false`,
	} {
		if !strings.Contains(rr.Body.String(), want) {
			t.Fatalf("disconnect response missing %s: %s", want, rr.Body.String())
		}
	}
	if got := sendHeartbeat(enrolled.AgentCredential); got.Code != http.StatusUnauthorized {
		t.Fatalf("old credential heartbeat=%d %s", got.Code, got.Body.String())
	}

	rr = requestJSON(t, app.handler, http.MethodGet, "/api/v1/fleet/nodes", "", adminCookie, "")
	if rr.Code != http.StatusOK {
		t.Fatalf("list after disconnect=%d %s", rr.Code, rr.Body.String())
	}
	for _, stale := range []string{`"agent_version":"1.1.9"`, `"hostname":"srv-01.example"`, `"os_name":"Ubuntu"`} {
		if strings.Contains(rr.Body.String(), stale) {
			t.Fatalf("disconnect retained stale runtime metadata %s: %s", stale, rr.Body.String())
		}
	}

	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/nodes/srv-01/disconnect", `{}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusOK || !strings.Contains(rr.Body.String(), `"disconnected":false`) {
		t.Fatalf("idempotent disconnect=%d %s", rr.Code, rr.Body.String())
	}
}

func TestFleetDisconnectRevokesPendingEnrollmentAndRequiresAdmin(t *testing.T) {
	app := newTestApp(t)
	adminCookie, adminCSRF := login(t, app, "admin", app.adminPassword)

	rr := requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/nodes", `{"name":"srv-02","address":"10.10.0.12"}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusCreated {
		t.Fatalf("create=%d %s", rr.Code, rr.Body.String())
	}
	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/nodes/srv-02/enrollment", `{}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusCreated {
		t.Fatalf("prepare=%d %s", rr.Code, rr.Body.String())
	}
	var prepared struct {
		Enrollment struct {
			Token string `json:"token"`
		} `json:"enrollment"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &prepared); err != nil {
		t.Fatal(err)
	}

	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/rbac/users", `{"username":"fleetviewer","password":"fleetviewer-password-123","role":"viewer"}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusCreated {
		t.Fatalf("create viewer=%d %s", rr.Code, rr.Body.String())
	}
	viewerCookie, viewerCSRF := login(t, app, "fleetviewer", "fleetviewer-password-123")
	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/nodes/srv-02/disconnect", `{}`, viewerCookie, viewerCSRF)
	if rr.Code != http.StatusForbidden {
		t.Fatalf("viewer disconnect=%d %s", rr.Code, rr.Body.String())
	}

	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/nodes/srv-02/disconnect", `{}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusOK || !strings.Contains(rr.Body.String(), `"disconnected":true`) {
		t.Fatalf("admin disconnect=%d %s", rr.Code, rr.Body.String())
	}

	enrollBody := `{"node_id":"srv-02","token":"` + prepared.Enrollment.Token + `","agent_version":"1.1.9"}`
	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/enroll", enrollBody, nil, "")
	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("revoked enrollment token=%d %s", rr.Code, rr.Body.String())
	}

	rr = requestJSON(t, app.handler, http.MethodGet, "/api/v1/fleet/capabilities", "", adminCookie, "")
	if rr.Code != http.StatusOK || !strings.Contains(rr.Body.String(), `"node_disconnect":["admin"]`) {
		t.Fatalf("disconnect capability=%d %s", rr.Code, rr.Body.String())
	}
}
