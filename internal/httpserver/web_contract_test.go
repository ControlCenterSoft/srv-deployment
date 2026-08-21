package httpserver

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func readWebAsset(t *testing.T, path string) string {
	t.Helper()
	b, err := webFS.ReadFile(path)
	if err != nil {
		t.Fatalf("read embedded asset %s: %v", path, err)
	}
	return string(b)
}

func TestWebStylesHonorHiddenAttribute(t *testing.T) {
	css := readWebAsset(t, "web/styles.css")
	if !strings.Contains(css, "[hidden] { display: none !important; }") {
		t.Fatal("web styles must explicitly hide elements carrying the hidden attribute")
	}
}

func TestAdminWebJavaScriptSyntax(t *testing.T) {
	node, err := exec.LookPath("node")
	if err != nil {
		t.Skip("node is unavailable")
	}
	for _, asset := range []string{"web/app.js", "web/fleet-health.js", "web/network.js"} {
		name := filepath.Base(asset)
		path := filepath.Join(t.TempDir(), name)
		if err := os.WriteFile(path, []byte(readWebAsset(t, asset)), 0o600); err != nil {
			t.Fatalf("write %s: %v", asset, err)
		}
		cmd := exec.Command(node, "--check", path)
		if output, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("node --check %s failed: %v\n%s", asset, err, output)
		}
	}
}

func TestAdminWebFleetAgentCoverageContract(t *testing.T) {
	app := readWebAsset(t, "web/app.js")
	for _, required := range []string{
		`/api/v1/fleet/capabilities`,
		`data.agent_setup`,
		`renderFleetCapabilities`,
		`renderFleetAgentSetup`,
		`CONTROL_CENTER_URL=`,
		`FLEET_NODE_ID=`,
		`installerURL.origin !== window.location.origin`,
		`Токен не включается в команду или URL`,
	} {
		if !strings.Contains(app, required) {
			t.Fatalf("Fleet Agent Admin Web coverage is missing %q", required)
		}
	}
	if strings.Count(app, "data.enrollment.token") != 1 {
		t.Fatal("one-time enrollment token must only be rendered once and must not be embedded in the install command")
	}
	if !strings.Contains(app, `Promise.all([api("/api/v1/fleet/nodes"), api("/api/v1/fleet/capabilities")])`) {
		t.Fatal("Fleet inventory and capability metadata should load in parallel")
	}
}

func TestAdminWebRBACWorkflowContract(t *testing.T) {
	index := readWebAsset(t, "web/index.html")
	app := readWebAsset(t, "web/app.js")

	for _, required := range []string{"id=\"rbac-create-form\"", "id=\"rbac-username\"", "id=\"rbac-password\"", "id=\"rbac-role\"", "role=\"alert\""} {
		if !strings.Contains(index, required) {
			t.Fatalf("RBAC admin UI is missing %q", required)
		}
	}
	for _, required := range []string{"/api/v1/rbac/users", "/blocked", "loadRBAC()", "setUserBlocked"} {
		if !strings.Contains(app, required) {
			t.Fatalf("RBAC admin workflow is missing %q", required)
		}
	}
	if strings.Contains(app, "users.innerHTML") || strings.Contains(app, "data.users.map") {
		t.Fatal("RBAC API data must be rendered through DOM text nodes, not HTML interpolation")
	}
}

func TestAdminWebCrossPageRBACFormIsolation(t *testing.T) {
	network := readWebAsset(t, "web/network.js")
	if !strings.Contains(network, "#rbac-create-form") {
		t.Fatal("network navigation must hide the RBAC mutation form")
	}
}

func TestAdminWebKeyboardFocusContract(t *testing.T) {
	css := readWebAsset(t, "web/styles.css")
	if !strings.Contains(css, ":focus-visible") {
		t.Fatal("interactive controls must expose a visible keyboard focus state")
	}
}

func TestAdminWebFleetAccessibilityAndTabletContract(t *testing.T) {
	index := readWebAsset(t, "web/index.html")
	css := readWebAsset(t, "web/styles.css")

	for _, required := range []string{
		`id="fleet-form" class="workflow-form"`,
		`<label for="fleet-name">`,
		`<label for="fleet-address">`,
		`<label for="fleet-group">`,
		`<label for="fleet-environment">`,
		`id="fleet-nodes" role="status" aria-live="polite"`,
		`id="health" class="status" role="status" aria-live="polite"`,
	} {
		if !strings.Contains(index, required) {
			t.Fatalf("Fleet/Admin Web accessibility contract is missing %q", required)
		}
	}

	for _, required := range []string{
		`@media (max-width: 960px) and (min-width: 721px)`,
		`.shell { grid-template-columns: 210px minmax(0, 1fr); }`,
		`.compact-list li { min-width: 0; overflow-wrap: anywhere; }`,
		`.content { padding: 28px 24px; }`,
	} {
		if !strings.Contains(css, required) {
			t.Fatalf("tablet/long-content quality contract is missing %q", required)
		}
	}
}
