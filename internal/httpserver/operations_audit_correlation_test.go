package httpserver

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	"github.com/ControlCenterSoft/srv-deployment/internal/observability"
)

func TestOperationDetailCorrelatesBoundedAuditEvidence(t *testing.T) {
	app := newTestApp(t)
	adminCookie, adminCSRF := login(t, app, "admin", app.adminPassword)

	const password = "correlation-viewer-password-123"
	created := requestJSON(t, app.handler, http.MethodPost, "/api/v1/rbac/users", `{"username":"correlationviewer","password":"`+password+`","role":"viewer"}`, adminCookie, adminCSRF)
	if created.Code != http.StatusCreated {
		t.Fatalf("create viewer status=%d body=%s", created.Code, created.Body.String())
	}
	targetOperationID := created.Header().Get("X-Control-Center-Operation-ID")
	if targetOperationID == "" {
		t.Fatal("missing operation id for correlation fixture")
	}

	unrelated := requestJSON(t, app.handler, http.MethodGet, "/api/v1/network/interfaces", "", adminCookie, "")
	if unrelated.Code != http.StatusOK {
		t.Fatalf("network inventory status=%d body=%s", unrelated.Code, unrelated.Body.String())
	}

	detail := requestJSON(t, app.handler, http.MethodGet, "/api/v1/operations/"+targetOperationID, "", adminCookie, "")
	if detail.Code != http.StatusOK {
		t.Fatalf("detail status=%d body=%s", detail.Code, detail.Body.String())
	}
	if strings.Contains(detail.Body.String(), password) {
		t.Fatal("operation detail leaked request credential material")
	}

	var body struct {
		Audit struct {
			Events     []observability.AuditEvent `json:"events"`
			Count      int                        `json:"count"`
			Available  bool                       `json:"available"`
			Authorized bool                       `json:"authorized"`
			Bounded    bool                       `json:"bounded"`
			Limit      int                        `json:"limit"`
			Permission string                     `json:"permission"`
			ErrorCode  string                     `json:"error_code"`
		} `json:"audit"`
		Permissions map[string]string `json:"permissions"`
		Health      struct {
			Status         string `json:"status"`
			OperationStore bool   `json:"operation_store"`
			AuditLog       bool   `json:"audit_log"`
		} `json:"health"`
	}
	if err := json.Unmarshal(detail.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if !body.Audit.Available || !body.Audit.Authorized || !body.Audit.Bounded || body.Audit.Limit != 100 || body.Audit.Permission != "audit.read" || body.Audit.ErrorCode != "" {
		t.Fatalf("unexpected audit metadata: %+v", body.Audit)
	}
	if body.Permissions["read"] != "operations.read" || body.Permissions["audit"] != "audit.read" {
		t.Fatalf("unexpected permissions metadata: %+v", body.Permissions)
	}
	if body.Health.Status != "healthy" || !body.Health.OperationStore || !body.Health.AuditLog {
		t.Fatalf("unexpected health metadata: %+v", body.Health)
	}
	if body.Audit.Count != len(body.Audit.Events) || body.Audit.Count == 0 {
		t.Fatalf("unexpected audit count=%d events=%+v", body.Audit.Count, body.Audit.Events)
	}

	foundMutation := false
	for _, event := range body.Audit.Events {
		if event.OperationID != targetOperationID {
			t.Fatalf("unrelated audit event leaked into correlation: %+v", event)
		}
		if event.Action == "rbac.user.create" && event.Result == "success" && event.Target == "correlationviewer" {
			foundMutation = true
		}
	}
	if !foundMutation {
		t.Fatalf("missing correlated mutation audit evidence: %+v", body.Audit.Events)
	}
}
