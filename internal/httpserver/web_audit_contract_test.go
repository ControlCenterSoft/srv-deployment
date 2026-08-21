package httpserver

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestAdminWebAuditWorkflowContract(t *testing.T) {
	index := readWebAsset(t, "web/index.html")
	audit := readWebAsset(t, "web/audit.js")

	if !strings.Contains(index, `<script src="/audit.js" defer></script>`) {
		t.Fatal("Admin Web must load the audit workflow module")
	}
	for _, required := range []string{
		`data-page = 'audit'`,
		`button.textContent = 'Аудит'`,
		`currentUser?.role !== 'admin'`,
		`/api/v1/audit?limit=50`,
		`renderAuditEvents`,
		`event.operation_id`,
		`event.error_code`,
		`aria-live`,
		`Обновить журнал аудита`,
	} {
		if !strings.Contains(audit, required) {
			t.Fatalf("Admin Web audit coverage is missing %q", required)
		}
	}
	if strings.Contains(audit, "innerHTML") {
		t.Fatal("audit API data must be rendered through text nodes, not HTML interpolation")
	}
	if strings.Contains(audit, "remote_ip") {
		t.Fatal("Admin Web audit view must not surface remote IP data by default")
	}
	if strings.Contains(audit, "fetch(") {
		t.Fatal("audit workflow must reuse the authenticated same-origin api helper")
	}
	if len(audit) > 8*1024 {
		t.Fatalf("audit workflow exceeds the 8 KiB frontend budget: %d bytes", len(audit))
	}
}

func TestAdminWebAuditModuleSyntax(t *testing.T) {
	node, err := exec.LookPath("node")
	if err != nil {
		t.Skip("node is unavailable")
	}
	path := filepath.Join(t.TempDir(), "audit.js")
	if err := os.WriteFile(path, []byte(readWebAsset(t, "web/audit.js")), 0o600); err != nil {
		t.Fatalf("write audit.js: %v", err)
	}
	cmd := exec.Command(node, "--check", path)
	if output, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("node --check audit.js failed: %v\n%s", err, output)
	}
}

func TestAdminWebAuditPageIsolationContract(t *testing.T) {
	audit := readWebAsset(t, "web/audit.js")
	for _, selector := range []string{
		"#fleet-nodes", "#fleet-form", "#rbac-users", "#rbac-create-form", "#system-details",
		"#network-interfaces", "#operations-list", "#diagnostics-export", "#network-page",
	} {
		if !strings.Contains(audit, selector) {
			t.Fatalf("audit navigation must hide competing workflow %q", selector)
		}
	}
}
