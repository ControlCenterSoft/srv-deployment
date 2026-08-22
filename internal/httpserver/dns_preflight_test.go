package httpserver

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

func TestDNSResolverPreflightRequiresAdminCSRFAndPreviewFingerprint(t *testing.T) {
	app := newTestApp(t)
	payload := `{"nameservers":["192.0.2.53"],"search_domains":["example.test"],"expected_source_fingerprint":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}`

	anonymous := requestJSON(t, app.handler, http.MethodPost, "/api/v1/dns/resolver/preflight", payload, nil, "")
	if anonymous.Code != http.StatusUnauthorized {
		t.Fatalf("anonymous status=%d body=%s", anonymous.Code, anonymous.Body.String())
	}

	adminCookie, adminCSRF := login(t, app, "admin", app.adminPassword)
	missingCSRF := requestJSON(t, app.handler, http.MethodPost, "/api/v1/dns/resolver/preflight", payload, adminCookie, "")
	if missingCSRF.Code != http.StatusForbidden {
		t.Fatalf("missing csrf status=%d body=%s", missingCSRF.Code, missingCSRF.Body.String())
	}

	createViewer := requestJSON(t, app.handler, http.MethodPost, "/api/v1/rbac/users", `{"username":"dnspreflightviewer","password":"dnspreflightviewer-password-123","role":"viewer"}`, adminCookie, adminCSRF)
	if createViewer.Code != http.StatusCreated {
		t.Fatalf("create viewer status=%d body=%s", createViewer.Code, createViewer.Body.String())
	}
	viewerCookie, viewerCSRF := login(t, app, "dnspreflightviewer", "dnspreflightviewer-password-123")
	viewer := requestJSON(t, app.handler, http.MethodPost, "/api/v1/dns/resolver/preflight", payload, viewerCookie, viewerCSRF)
	if viewer.Code != http.StatusForbidden {
		t.Fatalf("viewer status=%d body=%s", viewer.Code, viewer.Body.String())
	}

	inventory := requestJSON(t, app.handler, http.MethodGet, "/api/v1/dns/resolver", "", adminCookie, "")
	if inventory.Code != http.StatusOK {
		t.Fatalf("inventory status=%d body=%s", inventory.Code, inventory.Body.String())
	}
	var current struct {
		Actual struct {
			Nameservers   []string `json:"nameservers"`
			SearchDomains []string `json:"search_domains"`
		} `json:"actual"`
		Management struct {
			PreflightSupported bool `json:"preflight_supported"`
		} `json:"management"`
	}
	if err := json.Unmarshal(inventory.Body.Bytes(), &current); err != nil {
		t.Fatal(err)
	}
	if !current.Management.PreflightSupported {
		t.Fatal("inventory does not advertise resolver preflight support")
	}

	previewRequest, err := json.Marshal(map[string]any{
		"nameservers":    current.Actual.Nameservers,
		"search_domains": current.Actual.SearchDomains,
	})
	if err != nil {
		t.Fatal(err)
	}
	preview := requestJSON(t, app.handler, http.MethodPost, "/api/v1/dns/resolver/preview", string(previewRequest), adminCookie, adminCSRF)
	if preview.Code != http.StatusOK {
		t.Fatalf("preview status=%d body=%s", preview.Code, preview.Body.String())
	}
	var previewBody struct {
		SourceFingerprint string `json:"source_fingerprint"`
	}
	if err := json.Unmarshal(preview.Body.Bytes(), &previewBody); err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(previewBody.SourceFingerprint, "sha256:") {
		t.Fatalf("preview source fingerprint=%q", previewBody.SourceFingerprint)
	}

	missingFingerprint, err := json.Marshal(map[string]any{
		"nameservers":    current.Actual.Nameservers,
		"search_domains": current.Actual.SearchDomains,
	})
	if err != nil {
		t.Fatal(err)
	}
	missingFingerprintResult := requestJSON(t, app.handler, http.MethodPost, "/api/v1/dns/resolver/preflight", string(missingFingerprint), adminCookie, adminCSRF)
	if missingFingerprintResult.Code != http.StatusBadRequest {
		t.Fatalf("missing fingerprint status=%d body=%s", missingFingerprintResult.Code, missingFingerprintResult.Body.String())
	}

	requestBody, err := json.Marshal(map[string]any{
		"nameservers":                 current.Actual.Nameservers,
		"search_domains":              current.Actual.SearchDomains,
		"expected_source_fingerprint": previewBody.SourceFingerprint,
	})
	if err != nil {
		t.Fatal(err)
	}

	rr := requestJSON(t, app.handler, http.MethodPost, "/api/v1/dns/resolver/preflight", string(requestBody), adminCookie, adminCSRF)
	if rr.Code != http.StatusOK {
		t.Fatalf("preflight status=%d body=%s", rr.Code, rr.Body.String())
	}
	var body struct {
		Preflight struct {
			Schema                int      `json:"schema"`
			Passed                bool     `json:"passed"`
			NoOp                  bool     `json:"no_op"`
			ApplySupported        bool     `json:"apply_supported"`
			SourceFingerprint     string   `json:"source_fingerprint"`
			Blockers              []string `json:"blockers"`
			RequiredExecutorSteps []string `json:"required_executor_steps"`
		} `json:"preflight"`
		Management struct {
			PreflightSupported bool   `json:"preflight_supported"`
			ApplySupported     bool   `json:"apply_supported"`
			Reason             string `json:"reason"`
		} `json:"management"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.Preflight.Schema != 1 || !body.Preflight.Passed || !body.Preflight.NoOp || body.Preflight.ApplySupported {
		t.Fatalf("unexpected preflight=%+v", body.Preflight)
	}
	if body.Preflight.SourceFingerprint != previewBody.SourceFingerprint || len(body.Preflight.Blockers) != 0 || len(body.Preflight.RequiredExecutorSteps) != 4 {
		t.Fatalf("preflight evidence=%+v", body.Preflight)
	}
	if !body.Management.PreflightSupported || body.Management.ApplySupported || body.Management.Reason != "recovery_executor_not_implemented" {
		t.Fatalf("management=%+v", body.Management)
	}
}

func TestDNSResolverPreflightViewerDenialIsAudited(t *testing.T) {
	app := newTestApp(t)
	adminCookie, adminCSRF := login(t, app, "admin", app.adminPassword)
	createViewer := requestJSON(t, app.handler, http.MethodPost, "/api/v1/rbac/users", `{"username":"dnspreflightaudit","password":"dnspreflightaudit-password-123","role":"viewer"}`, adminCookie, adminCSRF)
	if createViewer.Code != http.StatusCreated {
		t.Fatalf("create viewer status=%d body=%s", createViewer.Code, createViewer.Body.String())
	}
	viewerCookie, viewerCSRF := login(t, app, "dnspreflightaudit", "dnspreflightaudit-password-123")
	denied := requestJSON(t, app.handler, http.MethodPost, "/api/v1/dns/resolver/preflight", `{"nameservers":["192.0.2.53"],"search_domains":["example.test"],"expected_source_fingerprint":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}`, viewerCookie, viewerCSRF)
	if denied.Code != http.StatusForbidden {
		t.Fatalf("viewer preflight status=%d body=%s", denied.Code, denied.Body.String())
	}

	audit := requestJSON(t, app.handler, http.MethodGet, "/api/v1/audit?limit=100", "", adminCookie, "")
	if audit.Code != http.StatusOK {
		t.Fatalf("audit status=%d body=%s", audit.Code, audit.Body.String())
	}
	var body struct {
		Events []struct {
			Actor     string `json:"actor"`
			Action    string `json:"action"`
			Result    string `json:"result"`
			ErrorCode string `json:"error_code"`
		} `json:"events"`
	}
	if err := json.Unmarshal(audit.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	for _, event := range body.Events {
		if event.Actor == "dnspreflightaudit" && event.Action == "dns.resolver.preflight" && event.Result == "denied" && event.ErrorCode == "permission_denied" {
			return
		}
	}
	t.Fatalf("viewer denial was not audited as dns.resolver.preflight: %+v", body.Events)
}
