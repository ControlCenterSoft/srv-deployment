package httpserver

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/ControlCenterSoft/srv-deployment/internal/observability"
	"github.com/ControlCenterSoft/srv-deployment/internal/operations"
)

func TestOperationDetailContractRBACAndAudit(t *testing.T) {
	app := newTestApp(t)
	adminCookie, adminCSRF := login(t, app, "admin", app.adminPassword)

	created := requestJSON(t, app.handler, http.MethodPost, "/api/v1/rbac/users", `{"username":"detailviewer","password":"detail-viewer-password-123","role":"viewer"}`, adminCookie, adminCSRF)
	if created.Code != http.StatusCreated {
		t.Fatalf("create viewer status=%d body=%s", created.Code, created.Body.String())
	}
	targetOperationID := created.Header().Get("X-Control-Center-Operation-ID")
	if targetOperationID == "" {
		t.Fatal("missing operation id for fixture mutation")
	}

	detail := requestJSON(t, app.handler, http.MethodGet, "/api/v1/operations/"+targetOperationID, "", adminCookie, "")
	if detail.Code != http.StatusOK {
		t.Fatalf("detail status=%d body=%s", detail.Code, detail.Body.String())
	}
	var body struct {
		ContractVersion int               `json:"contract_version"`
		Operation       operations.Record `json:"operation"`
		Permissions     map[string]string `json:"permissions"`
		Health          struct {
			Status         string `json:"status"`
			OperationStore bool   `json:"operation_store"`
		} `json:"health"`
		ObservedAt string `json:"observed_at"`
	}
	if err := json.Unmarshal(detail.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.ContractVersion != 1 || body.Operation.ID != targetOperationID || body.Permissions["read"] != "operations.read" {
		t.Fatalf("unexpected detail contract: %+v", body)
	}
	if body.Health.Status != "healthy" || !body.Health.OperationStore || body.ObservedAt == "" {
		t.Fatalf("unexpected detail health metadata: %+v", body.Health)
	}

	invalid := requestJSON(t, app.handler, http.MethodGet, "/api/v1/operations/bad%20id", "", adminCookie, "")
	if invalid.Code != http.StatusBadRequest || responseErrorCode(t, invalid) != "invalid_operation_id" {
		t.Fatalf("invalid id status=%d body=%s", invalid.Code, invalid.Body.String())
	}
	missing := requestJSON(t, app.handler, http.MethodGet, "/api/v1/operations/missing-operation", "", adminCookie, "")
	if missing.Code != http.StatusNotFound || responseErrorCode(t, missing) != "operation_not_found" {
		t.Fatalf("missing id status=%d body=%s", missing.Code, missing.Body.String())
	}

	viewerCookie, _ := login(t, app, "detailviewer", "detail-viewer-password-123")
	denied := requestJSON(t, app.handler, http.MethodGet, "/api/v1/operations/"+targetOperationID, "", viewerCookie, "")
	if denied.Code != http.StatusForbidden || responseErrorCode(t, denied) != "permission_denied" {
		t.Fatalf("viewer detail status=%d body=%s", denied.Code, denied.Body.String())
	}
	anonymous := requestJSON(t, app.handler, http.MethodGet, "/api/v1/operations/"+targetOperationID, "", nil, "")
	if anonymous.Code != http.StatusUnauthorized || responseErrorCode(t, anonymous) != "authentication_required" {
		t.Fatalf("anonymous detail status=%d body=%s", anonymous.Code, anonymous.Body.String())
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
	want := map[string]bool{
		"success/":                    false,
		"failed/invalid_operation_id": false,
		"failed/operation_not_found":  false,
		"denied/permission_denied":    false,
	}
	for _, event := range auditBody.Events {
		if event.Action != "operations.detail.read" {
			continue
		}
		key := event.Result + "/" + event.ErrorCode
		if _, ok := want[key]; ok {
			want[key] = true
		}
	}
	for key, seen := range want {
		if !seen {
			t.Fatalf("missing operations.detail.read audit event %q: %+v", key, auditBody.Events)
		}
	}
}

func responseErrorCode(t *testing.T, rr *httptest.ResponseRecorder) string {
	t.Helper()
	var body struct {
		Error struct {
			Code string `json:"code"`
		} `json:"error"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	return body.Error.Code
}
