package httpserver

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestContractLabFleetDisconnectAllowsFreshReEnrollmentAndRotatesCredential(t *testing.T) {
	app := newTestApp(t)
	adminCookie, adminCSRF := login(t, app, "admin", app.adminPassword)

	rr := requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/nodes", `{"name":"reconnect-node","address":"10.30.0.21"}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusCreated {
		t.Fatalf("create node=%d body=%s", rr.Code, rr.Body.String())
	}

	prepare := func() string {
		t.Helper()
		rr := requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/nodes/reconnect-node/enrollment", `{}`, adminCookie, adminCSRF)
		if rr.Code != http.StatusCreated {
			t.Fatalf("prepare enrollment=%d body=%s", rr.Code, rr.Body.String())
		}
		var prepared struct {
			Enrollment struct {
				Token string `json:"token"`
			} `json:"enrollment"`
		}
		if err := json.Unmarshal(rr.Body.Bytes(), &prepared); err != nil {
			t.Fatal(err)
		}
		if prepared.Enrollment.Token == "" {
			t.Fatal("missing enrollment token")
		}
		return prepared.Enrollment.Token
	}

	enroll := func(token, version string) string {
		t.Helper()
		body := `{"node_id":"reconnect-node","token":"` + token + `","agent_version":"` + version + `"}`
		rr := requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/enroll", body, nil, "")
		if rr.Code != http.StatusOK {
			t.Fatalf("enroll=%d body=%s", rr.Code, rr.Body.String())
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
		return enrolled.AgentCredential
	}

	heartbeatBody := func(version string) string {
		return `{"node_id":"reconnect-node","agent_version":"` + version + `","hostname":"reconnect-node.example","os_name":"Ubuntu","os_version":"26.04","architecture":"amd64"}`
	}
	sendHeartbeat := func(credential, version string) *httptest.ResponseRecorder {
		t.Helper()
		req := httptest.NewRequest(http.MethodPost, "/api/v1/fleet/heartbeat", strings.NewReader(heartbeatBody(version)))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", "Bearer "+credential)
		out := httptest.NewRecorder()
		app.handler.ServeHTTP(out, req)
		return out
	}

	firstToken := prepare()
	firstCredential := enroll(firstToken, "1.1.9")
	if got := sendHeartbeat(firstCredential, "1.1.9"); got.Code != http.StatusOK {
		t.Fatalf("initial heartbeat=%d body=%s", got.Code, got.Body.String())
	}

	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/nodes/reconnect-node/disconnect", `{}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusOK || !strings.Contains(rr.Body.String(), `"re_enrollment_required":true`) {
		t.Fatalf("disconnect=%d body=%s", rr.Code, rr.Body.String())
	}

	secondToken := prepare()
	if secondToken == firstToken {
		t.Fatal("fresh re-enrollment must rotate the enrollment token")
	}
	secondCredential := enroll(secondToken, "1.1.10")
	if secondCredential == firstCredential {
		t.Fatal("fresh re-enrollment must rotate the agent credential")
	}

	if got := sendHeartbeat(firstCredential, "1.1.9"); got.Code != http.StatusUnauthorized {
		t.Fatalf("revoked first credential after re-enrollment=%d body=%s", got.Code, got.Body.String())
	}
	if got := sendHeartbeat(secondCredential, "1.1.10"); got.Code != http.StatusOK {
		t.Fatalf("fresh credential heartbeat=%d body=%s", got.Code, got.Body.String())
	}

	rr = requestJSON(t, app.handler, http.MethodGet, "/api/v1/fleet/nodes", "", adminCookie, "")
	if rr.Code != http.StatusOK {
		t.Fatalf("fleet inventory=%d body=%s", rr.Code, rr.Body.String())
	}
	for _, want := range []string{`"status":"enrolled"`, `"agent_version":"1.1.10"`, `"hostname":"reconnect-node.example"`} {
		if !strings.Contains(rr.Body.String(), want) {
			t.Fatalf("re-enrolled inventory missing %s: %s", want, rr.Body.String())
		}
	}
	for _, secret := range []string{firstToken, secondToken, firstCredential, secondCredential} {
		if strings.Contains(rr.Body.String(), secret) {
			t.Fatal("fleet inventory leaked enrollment or agent credential material")
		}
	}
}
