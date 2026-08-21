package httpserver

import (
	"encoding/json"
	"net/http"
	"testing"
)

func TestDNSResolverPreviewViewerDenialIsAudited(t *testing.T) {
	app := newTestApp(t)
	adminCookie, adminCSRF := login(t, app, "admin", app.adminPassword)

	createViewer := requestJSON(
		t,
		app.handler,
		http.MethodPost,
		"/api/v1/rbac/users",
		`{"username":"dnsauditviewer","password":"dnsauditviewer-password-123","role":"viewer"}`,
		adminCookie,
		adminCSRF,
	)
	if createViewer.Code != http.StatusCreated {
		t.Fatalf("create viewer status=%d body=%s", createViewer.Code, createViewer.Body.String())
	}
	viewerCookie, viewerCSRF := login(t, app, "dnsauditviewer", "dnsauditviewer-password-123")

	denied := requestJSON(
		t,
		app.handler,
		http.MethodPost,
		"/api/v1/dns/resolver/preview",
		`{"nameservers":["192.0.2.53"],"search_domains":["example.test"]}`,
		viewerCookie,
		viewerCSRF,
	)
	if denied.Code != http.StatusForbidden {
		t.Fatalf("viewer preview status=%d body=%s", denied.Code, denied.Body.String())
	}

	audit := requestJSON(t, app.handler, http.MethodGet, "/api/v1/audit?limit=100", "", adminCookie, "")
	if audit.Code != http.StatusOK {
		t.Fatalf("audit status=%d body=%s", audit.Code, audit.Body.String())
	}
	var body struct {
		Events []struct {
			Actor     string `json:"actor"`
			Role      string `json:"role"`
			Action    string `json:"action"`
			Result    string `json:"result"`
			ErrorCode string `json:"error_code"`
		} `json:"events"`
	}
	if err := json.Unmarshal(audit.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	for _, event := range body.Events {
		if event.Actor == "dnsauditviewer" &&
			event.Role == "viewer" &&
			event.Action == "dns.resolver.preview" &&
			event.Result == "denied" &&
			event.ErrorCode == "permission_denied" {
			return
		}
	}
	t.Fatalf("viewer permission denial was not recorded as dns.resolver.preview audit event: %+v", body.Events)
}
