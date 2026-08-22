package httpserver

import (
	"strings"
	"testing"
)

func TestAdminWebOperationDetailWorkflowContract(t *testing.T) {
	app := readWebAsset(t, "web/app.js")

	for _, required := range []string{
		`/api/v1/operations?limit=10`,
		`/api/v1/operations/${encodeURIComponent(operationID)}`,
		`loadRecentOperations`,
		`loadOperationDetail`,
		`renderOperationDetail`,
		`renderOperationAudit`,
		`Открыть детали операции`,
		`Данные операции и audit correlation загружаются напрямую из Core`,
	} {
		if !strings.Contains(app, required) {
			t.Fatalf("operation detail Admin Web workflow is missing %q", required)
		}
	}

	if strings.Contains(app, "/api/v1/operations/incidents") {
		t.Fatal("Experience must not consume the still-unmerged incidents contract")
	}
}

func TestAdminWebOperationDetailStatesAndAccessibility(t *testing.T) {
	app := readWebAsset(t, "web/app.js")

	for _, required := range []string{
		`Загрузка последних операций…`,
		`Операций пока нет.`,
		`Не удалось загрузить операции:`,
		`Загрузка деталей операции`,
		`Не удалось загрузить детали операции`,
		`role = "status"`,
		`aria-live`,
		`role = "alert"`,
		`button.disabled = true`,
		`button.disabled = false`,
		`operationDetailGeneration += 1`,
		`if (generation !== operationDetailGeneration) return`,
	} {
		if !strings.Contains(app, required) {
			t.Fatalf("operation detail loading/error/empty/accessibility contract is missing %q", required)
		}
	}
}

func TestAdminWebOperationDetailSupersededRequestRestoresButton(t *testing.T) {
	app := readWebAsset(t, "web/app.js")

	if !strings.Contains(app, `if (button.isConnected) button.disabled = false;`) {
		t.Fatal("operation detail request must restore its originating connected button when the request settles")
	}
	if strings.Contains(app, `generation === operationDetailGeneration && button.isConnected`) {
		t.Fatal("superseded operation detail requests must not leave their originating buttons disabled")
	}
	if strings.Count(app, `if (generation !== operationDetailGeneration) return`) < 2 {
		t.Fatal("stale operation detail success/error rendering must remain suppressed")
	}
}

func TestAdminWebOperationDetailAuditAuthorityContract(t *testing.T) {
	app := readWebAsset(t, "web/app.js")

	for _, required := range []string{
		`detail.audit?.authorized === false`,
		`detail.audit?.available === false`,
		`Коррелированный audit недоступен для текущей роли.`,
		`Core сообщил, что audit correlation временно недоступна`,
		`Связанных audit-событий нет.`,
		`detail.health?.status === "degraded"`,
		`detail.audit?.events || []`,
		`event.action || "—"`,
		`event.result || "—"`,
		`event.error_code ?`,
	} {
		if !strings.Contains(app, required) {
			t.Fatalf("operation detail Core/audit authority contract is missing %q", required)
		}
	}
}
