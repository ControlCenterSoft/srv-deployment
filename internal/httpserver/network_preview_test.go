package httpserver

import (
	"encoding/json"
	"net/http"
	"testing"
)

func TestNetworkAddressPreviewRequiresAdminAndCSRF(t *testing.T) {
	app := newTestApp(t)
	payload, err := json.Marshal(map[string]any{"interface": "definitely-missing", "cidr": "192.0.2.10/24"})
	if err != nil {
		t.Fatal(err)
	}
	bodyJSON := string(payload)

	anonymous := requestJSON(t, app.handler, http.MethodPost, "/api/v1/network/address-change/preview", bodyJSON, nil, "")
	if anonymous.Code != http.StatusUnauthorized {
		t.Fatalf("anonymous status=%d body=%s", anonymous.Code, anonymous.Body.String())
	}

	adminCookie, csrf := login(t, app, "admin", app.adminPassword)
	missingCSRF := requestJSON(t, app.handler, http.MethodPost, "/api/v1/network/address-change/preview", bodyJSON, adminCookie, "")
	if missingCSRF.Code != http.StatusForbidden {
		t.Fatalf("missing csrf status=%d body=%s", missingCSRF.Code, missingCSRF.Body.String())
	}

	invalid := requestJSON(t, app.handler, http.MethodPost, "/api/v1/network/address-change/preview", bodyJSON, adminCookie, csrf)
	if invalid.Code != http.StatusBadRequest {
		t.Fatalf("invalid interface status=%d body=%s", invalid.Code, invalid.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(invalid.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	errBody, _ := body["error"].(map[string]any)
	if errBody["code"] != "network_validation_failed" {
		t.Fatalf("error=%v", errBody)
	}
}
