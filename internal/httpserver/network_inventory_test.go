package httpserver

import (
	"encoding/json"
	"net/http"
	"testing"
)

func TestNetworkInventoryRequiresAuthenticationAndReturnsInterfaces(t *testing.T) {
	app := newTestApp(t)

	anonymous := requestJSON(t, app.handler, http.MethodGet, "/api/v1/network/interfaces", "", nil, "")
	if anonymous.Code != http.StatusUnauthorized {
		t.Fatalf("anonymous status=%d body=%s", anonymous.Code, anonymous.Body.String())
	}

	cookie, _ := login(t, app, "admin", app.adminPassword)
	rr := requestJSON(t, app.handler, http.MethodGet, "/api/v1/network/interfaces", "", cookie, "")
	if rr.Code != http.StatusOK {
		t.Fatalf("network inventory status=%d body=%s", rr.Code, rr.Body.String())
	}

	var body struct {
		Count      int `json:"count"`
		Interfaces []struct {
			Name      string   `json:"name"`
			Index     int      `json:"index"`
			MTU       int      `json:"mtu"`
			Flags     []string `json:"flags"`
			Addresses []string `json:"addresses"`
		} `json:"interfaces"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.Count == 0 || len(body.Interfaces) != body.Count {
		t.Fatalf("invalid inventory count=%d interfaces=%d", body.Count, len(body.Interfaces))
	}
	if body.Interfaces[0].Name == "" || body.Interfaces[0].Index <= 0 {
		t.Fatalf("invalid first interface: %+v", body.Interfaces[0])
	}
}
