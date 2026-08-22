package httpserver

import (
	"encoding/json"
	"net/http"
	"testing"

	networkmodel "github.com/ControlCenterSoft/srv-deployment/internal/network"
)

func TestNetworkAddressPreflightRequiresAuthCSRFAndFreshPreview(t *testing.T) {
	app := newTestApp(t)
	invalidBody := `{"interface":"missing","cidr":"192.0.2.20/24","expected_source_fingerprint":"sha256:not-valid"}`

	anonymous := requestJSON(t, app.handler, http.MethodPost, "/api/v1/network/address-change/preflight", invalidBody, nil, "")
	if anonymous.Code != http.StatusUnauthorized {
		t.Fatalf("anonymous status=%d body=%s", anonymous.Code, anonymous.Body.String())
	}

	adminCookie, csrf := login(t, app, "admin", app.adminPassword)
	missingCSRF := requestJSON(t, app.handler, http.MethodPost, "/api/v1/network/address-change/preflight", invalidBody, adminCookie, "")
	if missingCSRF.Code != http.StatusForbidden {
		t.Fatalf("missing csrf status=%d body=%s", missingCSRF.Code, missingCSRF.Body.String())
	}

	invalid := requestJSON(t, app.handler, http.MethodPost, "/api/v1/network/address-change/preflight", invalidBody, adminCookie, csrf)
	if invalid.Code != http.StatusBadRequest {
		t.Fatalf("invalid fingerprint status=%d body=%s", invalid.Code, invalid.Body.String())
	}
	var invalidResponse map[string]any
	if err := json.Unmarshal(invalid.Body.Bytes(), &invalidResponse); err != nil {
		t.Fatal(err)
	}
	errBody, _ := invalidResponse["error"].(map[string]any)
	if errBody["code"] != "network_validation_failed" {
		t.Fatalf("error=%v", errBody)
	}

	interfaces, err := networkmodel.Inventory()
	if err != nil {
		t.Fatal(err)
	}
	var target *networkmodel.Interface
	for i := range interfaces {
		loopback := false
		for _, flag := range interfaces[i].Flags {
			if flag == "loopback" {
				loopback = true
				break
			}
		}
		if !loopback && interfaces[i].Index > 0 {
			target = &interfaces[i]
			break
		}
	}
	if target == nil {
		t.Skip("no non-loopback interface available for network preflight contract test")
	}

	previewPayload, err := json.Marshal(map[string]string{"interface": target.Name, "cidr": "192.0.2.20/24"})
	if err != nil {
		t.Fatal(err)
	}
	preview := requestJSON(t, app.handler, http.MethodPost, "/api/v1/network/address-change/preview", string(previewPayload), adminCookie, csrf)
	if preview.Code != http.StatusOK {
		t.Fatalf("preview status=%d body=%s", preview.Code, preview.Body.String())
	}
	var previewResponse struct {
		SourceFingerprint string `json:"source_fingerprint"`
		Management        struct {
			PreflightSupported bool `json:"preflight_supported"`
			ApplySupported     bool `json:"apply_supported"`
		} `json:"management"`
	}
	if err := json.Unmarshal(preview.Body.Bytes(), &previewResponse); err != nil {
		t.Fatal(err)
	}
	if previewResponse.SourceFingerprint == "" || !previewResponse.Management.PreflightSupported || previewResponse.Management.ApplySupported {
		t.Fatalf("preview contract=%+v", previewResponse)
	}

	preflightPayload, err := json.Marshal(map[string]string{
		"interface":                   target.Name,
		"cidr":                        "192.0.2.20/24",
		"expected_source_fingerprint": previewResponse.SourceFingerprint,
	})
	if err != nil {
		t.Fatal(err)
	}
	preflight := requestJSON(t, app.handler, http.MethodPost, "/api/v1/network/address-change/preflight", string(preflightPayload), adminCookie, csrf)
	if preflight.Code != http.StatusOK {
		t.Fatalf("preflight status=%d body=%s", preflight.Code, preflight.Body.String())
	}
	var preflightResponse struct {
		Preflight struct {
			Passed         bool `json:"passed"`
			ApplySupported bool `json:"apply_supported"`
		} `json:"preflight"`
	}
	if err := json.Unmarshal(preflight.Body.Bytes(), &preflightResponse); err != nil {
		t.Fatal(err)
	}
	if !preflightResponse.Preflight.Passed || preflightResponse.Preflight.ApplySupported {
		t.Fatalf("preflight contract=%+v", preflightResponse.Preflight)
	}
}
