package httpserver

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestFleetCapabilitiesAndEnrollmentSetupContract(t *testing.T) {
	app := newTestApp(t)
	adminCookie, adminCSRF := login(t, app, "admin", app.adminPassword)

	rr := requestJSON(t, app.handler, http.MethodGet, "/api/v1/fleet/capabilities", "", adminCookie, "")
	if rr.Code != http.StatusOK {
		t.Fatalf("capabilities=%d %s", rr.Code, rr.Body.String())
	}
	for _, want := range []string{
		`"contract_version":1`,
		`"capability":"fleet"`,
		`"enrollment_prepare":["admin"]`,
		`"agent_heartbeat":"agent_bearer_credential"`,
		`"version":"1.1.0"`,
		`"heartbeat_interval_seconds":60`,
		`"arbitrary_shell":false`,
	} {
		if !strings.Contains(rr.Body.String(), want) {
			t.Fatalf("capability metadata missing %s: %s", want, rr.Body.String())
		}
	}

	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/rbac/users", `{"username":"fleetmeta","password":"fleetmeta-password-123","role":"viewer"}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusCreated {
		t.Fatalf("create viewer=%d %s", rr.Code, rr.Body.String())
	}
	viewerCookie, _ := login(t, app, "fleetmeta", "fleetmeta-password-123")
	rr = requestJSON(t, app.handler, http.MethodGet, "/api/v1/fleet/capabilities", "", viewerCookie, "")
	if rr.Code != http.StatusOK {
		t.Fatalf("viewer capabilities=%d %s", rr.Code, rr.Body.String())
	}

	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/nodes", `{"name":"srv-agent","address":"10.20.0.11"}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusCreated {
		t.Fatalf("create node=%d %s", rr.Code, rr.Body.String())
	}
	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/nodes/srv-agent/enrollment", `{}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusCreated {
		t.Fatalf("prepare enrollment=%d %s", rr.Code, rr.Body.String())
	}
	for _, want := range []string{
		`"agent_setup"`,
		`"install_path":"/api/v1/fleet/agent/install.sh"`,
		`"token_delivery":"interactive_prompt_or_root_only_file"`,
	} {
		if !strings.Contains(rr.Body.String(), want) {
			t.Fatalf("enrollment setup missing %s: %s", want, rr.Body.String())
		}
	}
}

func TestFleetAgentAssetsArePinnedAndSyntacticallyValid(t *testing.T) {
	app := newTestApp(t)
	digest := sha256.Sum256(fleetAgentSource)
	wantDigest := hex.EncodeToString(digest[:])

	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/fleet/agent/agent.py", nil)
	app.handler.ServeHTTP(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("agent source=%d %s", rr.Code, rr.Body.String())
	}
	if rr.Header().Get("X-Control-Center-Fleet-Agent-SHA256") != wantDigest {
		t.Fatalf("agent digest header=%q want=%q", rr.Header().Get("X-Control-Center-Fleet-Agent-SHA256"), wantDigest)
	}
	if rr.Body.String() != string(fleetAgentSource) {
		t.Fatal("served agent source differs from embedded bytes")
	}

	rr = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, "/api/v1/fleet/agent/install.sh", nil)
	app.handler.ServeHTTP(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("installer=%d %s", rr.Code, rr.Body.String())
	}
	installer := rr.Body.String()
	if strings.Contains(installer, "__AGENT_SHA256__") || !strings.Contains(installer, `AGENT_SHA256="`+wantDigest+`"`) {
		preview := installer
		if len(preview) > 500 {
			preview = preview[:500]
		}
		t.Fatalf("installer does not pin agent digest: %s", preview)
	}
	if strings.Contains(strings.ToLower(installer), "arbitrary_shell=true") {
		t.Fatal("installer must not enable arbitrary shell")
	}

	if bash, err := exec.LookPath("bash"); err == nil {
		cmd := exec.Command(bash, "-n")
		cmd.Stdin = strings.NewReader(installer)
		if output, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("installer bash -n failed: %v\n%s", err, output)
		}
	}
	if python, err := exec.LookPath("python3"); err == nil {
		agentPath := filepath.Join(t.TempDir(), "control-center-fleet-agent.py")
		if err := os.WriteFile(agentPath, fleetAgentSource, 0o700); err != nil {
			t.Fatal(err)
		}
		cmd := exec.Command(python, agentPath, "--self-test")
		if output, err := cmd.CombinedOutput(); err != nil || !strings.Contains(string(output), "FLEET_AGENT_SELF_TEST=PASSED") {
			t.Fatalf("agent self-test failed: %v\n%s", err, output)
		}
	}
}

func TestFleetAgentRejectsRemotePlainHTTPBeforeReadingCredential(t *testing.T) {
	python, err := exec.LookPath("python3")
	if err != nil {
		t.Skip("python3 is unavailable")
	}
	tmp := t.TempDir()
	agentPath := filepath.Join(tmp, "control-center-fleet-agent.py")
	configPath := filepath.Join(tmp, "agent.conf")
	credentialPath := filepath.Join(tmp, "missing-credential")
	if err := os.WriteFile(agentPath, fleetAgentSource, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(configPath, []byte("CONTROL_CENTER_URL=http://example.com\nFLEET_NODE_ID=srv-plain-http\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command(python, agentPath, "--config", configPath, "--credential-file", credentialPath)
	output, err := cmd.CombinedOutput()
	if err == nil {
		t.Fatalf("remote HTTP unexpectedly accepted: %s", output)
	}
	text := string(output)
	if !strings.Contains(text, "https_required") || strings.Contains(text, "credential_unavailable") {
		t.Fatalf("unexpected fail-closed result: %s", text)
	}
}

func TestFleetAgentRealEnrollmentAndHeartbeatAgainstAPI(t *testing.T) {
	python, err := exec.LookPath("python3")
	if err != nil {
		t.Skip("python3 is unavailable")
	}
	app := newTestApp(t)
	adminCookie, adminCSRF := login(t, app, "admin", app.adminPassword)

	rr := requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/nodes", `{"name":"srv-real-agent","address":"10.20.0.21","group":"office"}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusCreated {
		t.Fatalf("create node=%d %s", rr.Code, rr.Body.String())
	}
	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/nodes/srv-real-agent/enrollment", `{}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusCreated {
		t.Fatalf("prepare enrollment=%d %s", rr.Code, rr.Body.String())
	}
	var prepared struct {
		Enrollment struct {
			Token string `json:"token"`
		} `json:"enrollment"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &prepared); err != nil {
		t.Fatal(err)
	}
	if prepared.Enrollment.Token == "" {
		t.Fatal("missing enrollment token")
	}

	server := httptest.NewServer(app.handler)
	defer server.Close()
	tmp := t.TempDir()
	agentPath := filepath.Join(tmp, "control-center-fleet-agent.py")
	configPath := filepath.Join(tmp, "agent.conf")
	tokenPath := filepath.Join(tmp, "enrollment-token")
	credentialPath := filepath.Join(tmp, "agent-credential")
	if err := os.WriteFile(agentPath, fleetAgentSource, 0o700); err != nil {
		t.Fatal(err)
	}
	config := "CONTROL_CENTER_URL=" + server.URL + "\nFLEET_NODE_ID=srv-real-agent\n"
	if err := os.WriteFile(configPath, []byte(config), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(tokenPath, []byte(prepared.Enrollment.Token+"\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	cmd := exec.Command(python, agentPath, "--config", configPath, "--credential-file", credentialPath, "--enroll-token-file", tokenPath)
	if output, err := cmd.CombinedOutput(); err != nil || !strings.Contains(string(output), "FLEET_AGENT_ENROLL=PASSED") {
		t.Fatalf("agent enrollment failed: %v\n%s", err, output)
	}
	credentialBytes, err := os.ReadFile(credentialPath)
	if err != nil {
		t.Fatal(err)
	}
	credential := strings.TrimSpace(string(credentialBytes))
	if credential == "" || credential == prepared.Enrollment.Token {
		t.Fatal("agent credential was not provisioned independently")
	}
	info, err := os.Stat(credentialPath)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm()&0o077 != 0 {
		t.Fatalf("credential mode too open: %o", info.Mode().Perm())
	}

	cmd = exec.Command(python, agentPath, "--config", configPath, "--credential-file", credentialPath)
	if output, err := cmd.CombinedOutput(); err != nil || !strings.Contains(string(output), "FLEET_AGENT_HEARTBEAT=PASSED") {
		t.Fatalf("agent heartbeat failed: %v\n%s", err, output)
	}

	rr = requestJSON(t, app.handler, http.MethodGet, "/api/v1/fleet/nodes", "", adminCookie, "")
	for _, want := range []string{
		`"id":"srv-real-agent"`,
		`"health":"healthy"`,
		`"agent_version":"1.1.0"`,
		`"architecture":`,
		`"os_name":`,
	} {
		if !strings.Contains(rr.Body.String(), want) {
			t.Fatalf("fleet list missing %s: %s", want, rr.Body.String())
		}
	}
	if strings.Contains(rr.Body.String(), credential) || strings.Contains(rr.Body.String(), prepared.Enrollment.Token) {
		t.Fatal("fleet API leaked enrollment or agent credential")
	}
}
