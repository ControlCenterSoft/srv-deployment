package httpserver

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	"github.com/ControlCenterSoft/srv-deployment/internal/observability"
	"github.com/ControlCenterSoft/srv-deployment/internal/operations"
)

func TestOperationIncidentsReturnsBoundedFailedOperationsWithContractEvidence(t *testing.T) {
	app := newTestApp(t)
	adminCookie, adminCSRF := login(t, app, "admin", app.adminPassword)

	const password = "incident-viewer-password-123"
	created := requestJSON(t, app.handler, http.MethodPost, "/api/v1/rbac/users", `{"username":"incidentviewer","password":"`+password+`","role":"viewer"}`, adminCookie, adminCSRF)
	if created.Code != http.StatusCreated {
		t.Fatalf("create viewer status=%d body=%s", created.Code, created.Body.String())
	}
	successOperationID := created.Header().Get("X-Control-Center-Operation-ID")
	if successOperationID == "" {
		t.Fatal("missing successful operation id")
	}

	failed := requestJSON(t, app.handler, http.MethodPost, "/api/v1/rbac/users", `{"username":"incidentviewer","password":"`+password+`","role":"viewer"}`, adminCookie, adminCSRF)
	if failed.Code != http.StatusBadRequest {
		t.Fatalf("duplicate create status=%d body=%s", failed.Code, failed.Body.String())
	}
	failedOperationID := failed.Header().Get("X-Control-Center-Operation-ID")
	if failedOperationID == "" || failedOperationID == successOperationID {
		t.Fatalf("invalid failed operation id success=%q failed=%q", successOperationID, failedOperationID)
	}

	incidentsResponse := requestJSON(t, app.handler, http.MethodGet, "/api/v1/operations/incidents?limit=10", "", adminCookie, "")
	if incidentsResponse.Code != http.StatusOK {
		t.Fatalf("incidents status=%d body=%s", incidentsResponse.Code, incidentsResponse.Body.String())
	}
	if strings.Contains(incidentsResponse.Body.String(), password) {
		t.Fatal("incident response leaked request credential material")
	}

	var body struct {
		ContractVersion int                 `json:"contract_version"`
		Incidents       []operations.Record `json:"incidents"`
		Count           int                 `json:"count"`
		Bounded         bool                `json:"bounded"`
		Limit           int                 `json:"limit"`
		Statuses        []operations.Status `json:"statuses"`
		Permissions     map[string]string   `json:"permissions"`
		Health          struct {
			Status         string `json:"status"`
			OperationStore bool   `json:"operation_store"`
			AuditLog       bool   `json:"audit_log"`
		} `json:"health"`
		ObservedAt string `json:"observed_at"`
	}
	if err := json.Unmarshal(incidentsResponse.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.ContractVersion != 1 || !body.Bounded || body.Limit != 10 || body.Count != len(body.Incidents) || body.ObservedAt == "" {
		t.Fatalf("unexpected incident metadata: %+v", body)
	}
	if len(body.Statuses) != 2 || body.Statuses[0] != operations.StatusFailed || body.Statuses[1] != operations.StatusInterrupted {
		t.Fatalf("unexpected incident statuses: %+v", body.Statuses)
	}
	if body.Permissions["read"] != "operations.read" {
		t.Fatalf("unexpected permissions: %+v", body.Permissions)
	}
	if body.Health.Status != "healthy" || !body.Health.OperationStore || !body.Health.AuditLog {
		t.Fatalf("unexpected health: %+v", body.Health)
	}
	if len(body.Incidents) != 1 {
		t.Fatalf("unexpected incidents: %+v", body.Incidents)
	}
	incident := body.Incidents[0]
	if incident.ID != failedOperationID || incident.Status != operations.StatusFailed || incident.ErrorCode != "user_create_failed" {
		t.Fatalf("unexpected incident: %+v", incident)
	}
	if incident.ID == successOperationID {
		t.Fatalf("successful operation leaked into incident feed: %+v", incident)
	}

	invalid := requestJSON(t, app.handler, http.MethodGet, "/api/v1/operations/incidents?limit=0", "", adminCookie, "")
	if invalid.Code != http.StatusBadRequest || !strings.Contains(invalid.Body.String(), `"code":"invalid_limit"`) {
		t.Fatalf("invalid limit status=%d body=%s", invalid.Code, invalid.Body.String())
	}

	viewerCookie, _ := login(t, app, "incidentviewer", password)
	denied := requestJSON(t, app.handler, http.MethodGet, "/api/v1/operations/incidents", "", viewerCookie, "")
	if denied.Code != http.StatusForbidden || !strings.Contains(denied.Body.String(), `"code":"permission_denied"`) {
		t.Fatalf("viewer incidents status=%d body=%s", denied.Code, denied.Body.String())
	}

	anonymous := requestJSON(t, app.handler, http.MethodGet, "/api/v1/operations/incidents", "", nil, "")
	if anonymous.Code != http.StatusUnauthorized {
		t.Fatalf("anonymous incidents status=%d body=%s", anonymous.Code, anonymous.Body.String())
	}

	auditResponse := requestJSON(t, app.handler, http.MethodGet, "/api/v1/audit?limit=100", "", adminCookie, "")
	if auditResponse.Code != http.StatusOK {
		t.Fatalf("audit status=%d body=%s", auditResponse.Code, auditResponse.Body.String())
	}
	var auditBody struct {
		Events []observability.AuditEvent `json:"events"`
	}
	if err := json.Unmarshal(auditResponse.Body.Bytes(), &auditBody); err != nil {
		t.Fatal(err)
	}
	foundInvalidLimit := false
	foundViewerDenial := false
	for _, event := range auditBody.Events {
		if event.Action != "operations.incidents.read" {
			continue
		}
		if event.Result == "failed" && event.ErrorCode == "invalid_limit" {
			foundInvalidLimit = true
		}
		if event.Actor == "incidentviewer" && event.Result == "denied" && event.ErrorCode == "permission_denied" {
			foundViewerDenial = true
		}
	}
	if !foundInvalidLimit || !foundViewerDenial {
		t.Fatalf("missing incident audit evidence invalid_limit=%v viewer_denial=%v events=%+v", foundInvalidLimit, foundViewerDenial, auditBody.Events)
	}
}

func TestParseIncidentLimitIsStrictAndBounded(t *testing.T) {
	for _, tc := range []struct {
		path  string
		want  int
		valid bool
	}{
		{path: "/api/v1/operations/incidents", want: defaultIncidentLimit, valid: true},
		{path: "/api/v1/operations/incidents?limit=1", want: 1, valid: true},
		{path: "/api/v1/operations/incidents?limit=100", want: 100, valid: true},
		{path: "/api/v1/operations/incidents?limit=", valid: false},
		{path: "/api/v1/operations/incidents?limit=%20", valid: false},
		{path: "/api/v1/operations/incidents?limit=1&limit=2", valid: false},
		{path: "/api/v1/operations/incidents?limit=0", valid: false},
		{path: "/api/v1/operations/incidents?limit=101", valid: false},
		{path: "/api/v1/operations/incidents?limit=abc", valid: false},
	} {
		req, err := http.NewRequest(http.MethodGet, tc.path, nil)
		if err != nil {
			t.Fatal(err)
		}
		got, valid := parseIncidentLimit(req)
		if valid != tc.valid || got != tc.want {
			t.Fatalf("path=%s got=(%d,%v) want=(%d,%v)", tc.path, got, valid, tc.want, tc.valid)
		}
	}
}
