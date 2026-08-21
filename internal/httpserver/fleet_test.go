package httpserver

import (
	"net/http"
	"strings"
	"testing"
)

func TestFleetInventoryCreateListAndViewerRBAC(t *testing.T) {
	app := newTestApp(t)
	adminCookie, adminCSRF := login(t, app, "admin", app.adminPassword)

	rr := requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/nodes", `{"name":"srv-01","address":"10.10.0.11","group":"office","environment":"production"}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusCreated {
		t.Fatalf("create fleet node status=%d body=%s", rr.Code, rr.Body.String())
	}
	if !strings.Contains(rr.Body.String(), `"status":"pending_enrollment"`) {
		t.Fatalf("missing pending enrollment state: %s", rr.Body.String())
	}

	rr = requestJSON(t, app.handler, http.MethodGet, "/api/v1/fleet/nodes", "", adminCookie, "")
	if rr.Code != http.StatusOK || !strings.Contains(rr.Body.String(), `"srv-01"`) {
		t.Fatalf("list fleet nodes status=%d body=%s", rr.Code, rr.Body.String())
	}

	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/rbac/users", `{"username":"fleetviewer","password":"fleetviewer-password-123","role":"viewer"}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusCreated {
		t.Fatalf("create viewer status=%d body=%s", rr.Code, rr.Body.String())
	}
	viewerCookie, viewerCSRF := login(t, app, "fleetviewer", "fleetviewer-password-123")

	rr = requestJSON(t, app.handler, http.MethodGet, "/api/v1/fleet/nodes", "", viewerCookie, "")
	if rr.Code != http.StatusOK {
		t.Fatalf("viewer fleet read status=%d body=%s", rr.Code, rr.Body.String())
	}
	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/nodes", `{"name":"srv-02","address":"10.10.0.12"}`, viewerCookie, viewerCSRF)
	if rr.Code != http.StatusForbidden {
		t.Fatalf("viewer fleet write status=%d body=%s", rr.Code, rr.Body.String())
	}
}

func TestFleetMutationRequiresCSRF(t *testing.T) {
	app := newTestApp(t)
	adminCookie, _ := login(t, app, "admin", app.adminPassword)
	rr := requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/nodes", `{"name":"srv-01","address":"10.10.0.11"}`, adminCookie, "")
	if rr.Code != http.StatusForbidden {
		t.Fatalf("missing csrf status=%d body=%s", rr.Code, rr.Body.String())
	}
}
