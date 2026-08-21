package httpserver

import (
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
