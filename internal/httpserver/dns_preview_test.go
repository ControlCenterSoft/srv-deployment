package httpserver

import (
	"encoding/json"
	"net/http"
	"testing"
)

func TestDNSResolverPreviewRequiresAdminCSRFAndValidInput(t *testing.T) {
	app := newTestApp(t)
	invalidPayload := `{"nameservers":["0.0.0.0"],"search_domains":["example.test"]}`

	anonymous := requestJSON(t, app.handler, http.MethodPost, "/api/v1/dns/resolver/preview", invalidPayload, nil, "")
	if anonymous.Code != http.StatusUnauthorized {
		t.Fatalf("anonymous status=%d body=%s", anonymous.Code, anonymous.Body.String())
	}

	adminCookie, adminCSRF := login(t, app, "admin", app.adminPassword)
	missingCSRF := requestJSON(t, app.handler, http.MethodPost, "/api/v1/dns/resolver/preview", invalidPayload, adminCookie, "")
	if missingCSRF.Code != http.StatusForbidden {
		t.Fatalf("missing csrf status=%d body=%s", missingCSRF.Code, missingCSRF.Body.String())
	}

	createViewer := requestJSON(t, app.handler, http.MethodPost, "/api/v1/rbac/users", `{"username":"dnsviewer","password":"dnsviewer-password-123","role":"viewer"}`, adminCookie, adminCSRF)
	if createViewer.Code != http.StatusCreated {
		t.Fatalf("create viewer status=%d body=%s", createViewer.Code, createViewer.Body.String())
	}
	viewerCookie, viewerCSRF := login(t, app, "dnsviewer", "dnsviewer-password-123")
	viewer := requestJSON(t, app.handler, http.MethodPost, "/api/v1/dns/resolver/preview", invalidPayload, viewerCookie, viewerCSRF)
	if viewer.Code != http.StatusForbidden {
		t.Fatalf("viewer status=%d body=%s", viewer.Code, viewer.Body.String())
	}

	invalid := requestJSON(t, app.handler, http.MethodPost, "/api/v1/dns/resolver/preview", invalidPayload, adminCookie, adminCSRF)
	if invalid.Code != http.StatusBadRequest {
		t.Fatalf("invalid status=%d body=%s", invalid.Code, invalid.Body.String())
	}
	var invalidBody map[string]any
	if err := json.Unmarshal(invalid.Body.Bytes(), &invalidBody); err != nil {
		t.Fatal(err)
	}
	errBody, _ := invalidBody["error"].(map[string]any)
	if errBody["code"] != "dns_validation_failed" {
		t.Fatalf("error=%v", errBody)
	}
}

func TestDNSResolverPreviewReturnsNoOpDesiredActualAndRollback(t *testing.T) {
	app := newTestApp(t)
	adminCookie, adminCSRF := login(t, app, "admin", app.adminPassword)

	inventory := requestJSON(t, app.handler, http.MethodGet, "/api/v1/dns/resolver", "", adminCookie, "")
	if inventory.Code != http.StatusOK {
		t.Fatalf("inventory status=%d body=%s", inventory.Code, inventory.Body.String())
	}
	var current struct {
		Actual struct {
			Nameservers   []string `json:"nameservers"`
			SearchDomains []string `json:"search_domains"`
		} `json:"actual"`
	}
	if err := json.Unmarshal(inventory.Body.Bytes(), &current); err != nil {
		t.Fatal(err)
	}
	payload, err := json.Marshal(map[string]any{
		"nameservers":    current.Actual.Nameservers,
		"search_domains": current.Actual.SearchDomains,
	})
	if err != nil {
		t.Fatal(err)
	}

	rr := requestJSON(t, app.handler, http.MethodPost, "/api/v1/dns/resolver/preview", string(payload), adminCookie, adminCSRF)
	if rr.Code != http.StatusOK {
		t.Fatalf("preview status=%d body=%s", rr.Code, rr.Body.String())
	}
	var body struct {
		Plan struct {
			Schema         int      `json:"schema"`
			NoOp           bool     `json:"no_op"`
			ApplySupported bool     `json:"apply_supported"`
			Preconditions  []string `json:"preconditions"`
		} `json:"plan"`
		Desired struct {
			Nameservers []string `json:"nameservers"`
		} `json:"desired"`
		Actual struct {
			Nameservers []string `json:"nameservers"`
		} `json:"actual"`
		Rollback struct {
			Nameservers []string `json:"nameservers"`
		} `json:"rollback"`
		Management struct {
			PreviewSupported bool   `json:"preview_supported"`
			ApplySupported   bool   `json:"apply_supported"`
			Reason           string `json:"reason"`
		} `json:"management"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.Plan.Schema != 1 || !body.Plan.NoOp || body.Plan.ApplySupported || len(body.Plan.Preconditions) < 4 {
		t.Fatalf("unexpected plan=%+v", body.Plan)
	}
	if len(body.Desired.Nameservers) == 0 || len(body.Actual.Nameservers) == 0 || len(body.Rollback.Nameservers) == 0 {
		t.Fatalf("missing desired/actual/rollback: desired=%v actual=%v rollback=%v", body.Desired.Nameservers, body.Actual.Nameservers, body.Rollback.Nameservers)
	}
	if !body.Management.PreviewSupported || body.Management.ApplySupported || body.Management.Reason != "recovery_executor_not_implemented" {
		t.Fatalf("management=%+v", body.Management)
	}
}
