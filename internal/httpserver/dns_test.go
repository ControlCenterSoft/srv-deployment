package httpserver

import (
	"encoding/json"
	"net/http"
	"testing"
)

func TestDNSResolverInventoryRequiresAuthenticationAndReturnsActualState(t *testing.T) {
	app := newTestApp(t)

	anonymous := requestJSON(t, app.handler, http.MethodGet, "/api/v1/dns/resolver", "", nil, "")
	if anonymous.Code != http.StatusUnauthorized {
		t.Fatalf("anonymous status=%d body=%s", anonymous.Code, anonymous.Body.String())
	}

	cookie, _ := login(t, app, "admin", app.adminPassword)
	rr := requestJSON(t, app.handler, http.MethodGet, "/api/v1/dns/resolver", "", cookie, "")
	if rr.Code != http.StatusOK {
		t.Fatalf("resolver inventory status=%d body=%s", rr.Code, rr.Body.String())
	}

	var body struct {
		Actual struct {
			Schema         int      `json:"schema"`
			Managed        bool     `json:"managed"`
			ApplySupported bool     `json:"apply_supported"`
			Source         string   `json:"source"`
			SourceKind     string   `json:"source_kind"`
			Nameservers    []string `json:"nameservers"`
		} `json:"actual"`
		Desired    any `json:"desired"`
		Management struct {
			Supported bool   `json:"supported"`
			Reason    string `json:"reason"`
		} `json:"management"`
		ObservedAt string `json:"observed_at"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.Actual.Schema != 1 || body.Actual.Managed || body.Actual.ApplySupported {
		t.Fatalf("unexpected resolver management state: %+v", body.Actual)
	}
	if body.Actual.Source == "" || body.Actual.SourceKind == "" || len(body.Actual.Nameservers) == 0 {
		t.Fatalf("incomplete resolver inventory: %+v", body.Actual)
	}
	if body.Desired != nil {
		t.Fatalf("read-only foundation must not invent desired state: %v", body.Desired)
	}
	if body.Management.Supported || body.Management.Reason != "read_only_foundation" || body.ObservedAt == "" {
		t.Fatalf("unexpected management contract: %+v observed=%q", body.Management, body.ObservedAt)
	}
}
