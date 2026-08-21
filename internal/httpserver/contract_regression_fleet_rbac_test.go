package httpserver

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

type contractLabAgentSetup struct {
	Version                  string `json:"version"`
	InstallPath              string `json:"install_path"`
	SourcePath               string `json:"source_path"`
	HeartbeatIntervalSeconds int    `json:"heartbeat_interval_seconds"`
	RequiresHTTPS            bool   `json:"requires_https"`
	LoopbackHTTPForTesting   bool   `json:"loopback_http_for_testing"`
	RuntimeUser              string `json:"runtime_user"`
	ArbitraryShell           bool   `json:"arbitrary_shell"`
	CredentialShownOnce      bool   `json:"credential_shown_once"`
	TokenDelivery            string `json:"token_delivery"`
}

type contractLabCapabilities struct {
	ContractVersion int    `json:"contract_version"`
	Capability      string `json:"capability"`
	Permissions     struct {
		Read              []string `json:"read"`
		NodeCreate        []string `json:"node_create"`
		EnrollmentPrepare []string `json:"enrollment_prepare"`
		AgentEnroll       string   `json:"agent_enroll"`
		AgentHeartbeat    string   `json:"agent_heartbeat"`
	} `json:"permissions"`
	Agent  contractLabAgentSetup `json:"agent"`
	Health struct {
		HealthyMaxAgeSeconds int      `json:"healthy_max_age_seconds"`
		StaleMaxAgeSeconds   int      `json:"stale_max_age_seconds"`
		States               []string `json:"states"`
	} `json:"health"`
}

type contractLabEnrollmentResponse struct {
	Node struct {
		ID     string `json:"id"`
		Status string `json:"status"`
	} `json:"node"`
	Enrollment struct {
		Token   string `json:"token"`
		OneTime bool   `json:"one_time"`
	} `json:"enrollment"`
	AgentSetup contractLabAgentSetup `json:"agent_setup"`
}

type contractLabFleetInventory struct {
	Nodes []struct {
		ID         string `json:"id"`
		Status     string `json:"status"`
		UpdatedAt  string `json:"updated_at"`
		LastSeenAt string `json:"last_seen_at"`
	} `json:"nodes"`
	Summary struct {
		Total             int `json:"total"`
		PendingEnrollment int `json:"pending_enrollment"`
		Enrolled          int `json:"enrolled"`
		Healthy           int `json:"healthy"`
	} `json:"summary"`
}

func contractLabDecode[T any](t *testing.T, body []byte) T {
	t.Helper()
	var value T
	if err := json.Unmarshal(body, &value); err != nil {
		t.Fatalf("decode contract response: %v\n%s", err, body)
	}
	return value
}

func contractLabJSON(t *testing.T, value any) string {
	t.Helper()
	body, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	return string(body)
}

func TestContractLabFleetCapabilityPermissionMatrixAndSetupConsistency(t *testing.T) {
	app := newTestApp(t)

	rr := requestJSON(t, app.handler, http.MethodGet, "/api/v1/fleet/capabilities", "", nil, "")
	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("anonymous capabilities=%d body=%s", rr.Code, rr.Body.String())
	}

	adminCookie, adminCSRF := login(t, app, "admin", app.adminPassword)
	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/rbac/users", `{"username":"contractviewer","password":"contractviewer-password-123","role":"viewer"}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusCreated {
		t.Fatalf("create viewer=%d body=%s", rr.Code, rr.Body.String())
	}
	viewerCookie, viewerCSRF := login(t, app, "contractviewer", "contractviewer-password-123")

	rr = requestJSON(t, app.handler, http.MethodGet, "/api/v1/fleet/capabilities", "", viewerCookie, "")
	if rr.Code != http.StatusOK {
		t.Fatalf("viewer capabilities=%d body=%s", rr.Code, rr.Body.String())
	}
	capabilities := contractLabDecode[contractLabCapabilities](t, rr.Body.Bytes())
	if capabilities.ContractVersion != 1 || capabilities.Capability != "fleet" {
		t.Fatalf("unexpected capability identity: %+v", capabilities)
	}
	if strings.Join(capabilities.Permissions.Read, ",") != "admin,viewer" ||
		strings.Join(capabilities.Permissions.NodeCreate, ",") != "admin" ||
		strings.Join(capabilities.Permissions.EnrollmentPrepare, ",") != "admin" {
		t.Fatalf("permission metadata drift: %+v", capabilities.Permissions)
	}
	if capabilities.Permissions.AgentEnroll != "one_time_enrollment_token" || capabilities.Permissions.AgentHeartbeat != "agent_bearer_credential" {
		t.Fatalf("agent auth metadata drift: %+v", capabilities.Permissions)
	}
	if capabilities.Agent.Version != fleetAgentVersion || capabilities.Agent.HeartbeatIntervalSeconds != 60 ||
		!capabilities.Agent.RequiresHTTPS || !capabilities.Agent.LoopbackHTTPForTesting || capabilities.Agent.RuntimeUser != "control-center-fleet" ||
		capabilities.Agent.ArbitraryShell || !capabilities.Agent.CredentialShownOnce || capabilities.Agent.TokenDelivery != "interactive_prompt_or_root_only_file" {
		t.Fatalf("agent setup metadata drift: %+v", capabilities.Agent)
	}
	if capabilities.Health.HealthyMaxAgeSeconds != 120 || capabilities.Health.StaleMaxAgeSeconds != 900 ||
		strings.Join(capabilities.Health.States, ",") != "healthy,stale,offline,unknown" {
		t.Fatalf("health contract drift: %+v", capabilities.Health)
	}

	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/nodes", `{"name":"contract-node","address":"10.30.0.11"}`, viewerCookie, viewerCSRF)
	if rr.Code != http.StatusForbidden {
		t.Fatalf("viewer node create=%d body=%s", rr.Code, rr.Body.String())
	}

	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/nodes", `{"name":"contract-node","address":"10.30.0.11"}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusCreated {
		t.Fatalf("admin node create=%d body=%s", rr.Code, rr.Body.String())
	}
	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/nodes/contract-node/enrollment", `{}`, viewerCookie, viewerCSRF)
	if rr.Code != http.StatusForbidden {
		t.Fatalf("viewer enrollment prepare=%d body=%s", rr.Code, rr.Body.String())
	}

	rr = requestJSON(t, app.handler, http.MethodGet, "/api/v1/fleet/nodes", "", viewerCookie, "")
	inventory := contractLabDecode[contractLabFleetInventory](t, rr.Body.Bytes())
	if inventory.Summary.Total != 1 || inventory.Summary.PendingEnrollment != 1 || inventory.Summary.Enrolled != 0 || len(inventory.Nodes) != 1 || inventory.Nodes[0].Status != "pending_enrollment" {
		t.Fatalf("denied viewer mutations changed fleet state: %+v", inventory)
	}

	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/nodes/contract-node/enrollment", `{}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusCreated {
		t.Fatalf("admin enrollment prepare=%d body=%s", rr.Code, rr.Body.String())
	}
	prepared := contractLabDecode[contractLabEnrollmentResponse](t, rr.Body.Bytes())
	if prepared.Enrollment.Token == "" || !prepared.Enrollment.OneTime {
		t.Fatalf("invalid one-time enrollment contract: %+v", prepared.Enrollment)
	}
	if prepared.AgentSetup != capabilities.Agent {
		t.Fatalf("capabilities.agent and enrollment.agent_setup drifted:\ncapabilities=%+v\nenrollment=%+v", capabilities.Agent, prepared.AgentSetup)
	}
	setupJSON := contractLabJSON(t, prepared.AgentSetup)
	if strings.Contains(setupJSON, prepared.Enrollment.Token) {
		t.Fatal("agent_setup must never embed the one-time enrollment token")
	}
}

func TestContractLabFleetEnrollmentRotationOneTimeUseAndFailedHeartbeatIsNonMutating(t *testing.T) {
	app := newTestApp(t)
	adminCookie, adminCSRF := login(t, app, "admin", app.adminPassword)

	rr := requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/nodes", `{"name":"rotation-node","address":"10.30.0.12"}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusCreated {
		t.Fatalf("create node=%d body=%s", rr.Code, rr.Body.String())
	}

	prepare := func() contractLabEnrollmentResponse {
		rr := requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/nodes/rotation-node/enrollment", `{}`, adminCookie, adminCSRF)
		if rr.Code != http.StatusCreated {
			t.Fatalf("prepare enrollment=%d body=%s", rr.Code, rr.Body.String())
		}
		return contractLabDecode[contractLabEnrollmentResponse](t, rr.Body.Bytes())
	}
	first := prepare()
	second := prepare()
	if first.Enrollment.Token == "" || second.Enrollment.Token == "" || first.Enrollment.Token == second.Enrollment.Token {
		t.Fatal("enrollment prepare must rotate the one-time token")
	}

	enrollBody := func(token string) string {
		return contractLabJSON(t, map[string]string{"node_id": "rotation-node", "token": token, "agent_version": fleetAgentVersion})
	}
	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/enroll", enrollBody(first.Enrollment.Token), nil, "")
	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("rotated-out enrollment token accepted=%d body=%s", rr.Code, rr.Body.String())
	}
	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/enroll", enrollBody(second.Enrollment.Token), nil, "")
	if rr.Code != http.StatusOK {
		t.Fatalf("current enrollment token rejected=%d body=%s", rr.Code, rr.Body.String())
	}
	var enrolled struct {
		AgentCredential string `json:"agent_credential"`
	}
	enrolled = contractLabDecode[struct {
		AgentCredential string `json:"agent_credential"`
	}](t, rr.Body.Bytes())
	if enrolled.AgentCredential == "" || enrolled.AgentCredential == second.Enrollment.Token {
		t.Fatal("agent credential must be distinct from the one-time enrollment token")
	}

	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/fleet/enroll", enrollBody(second.Enrollment.Token), nil, "")
	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("reused one-time enrollment token accepted=%d body=%s", rr.Code, rr.Body.String())
	}

	rr = requestJSON(t, app.handler, http.MethodGet, "/api/v1/fleet/nodes", "", adminCookie, "")
	before := contractLabDecode[contractLabFleetInventory](t, rr.Body.Bytes())
	if before.Summary.Enrolled != 1 || len(before.Nodes) != 1 || before.Nodes[0].Status != "enrolled" {
		t.Fatalf("unexpected enrolled state: %+v", before)
	}
	if strings.Contains(rr.Body.String(), first.Enrollment.Token) || strings.Contains(rr.Body.String(), second.Enrollment.Token) ||
		strings.Contains(rr.Body.String(), enrolled.AgentCredential) || strings.Contains(rr.Body.String(), "agent_credential_hash") || strings.Contains(rr.Body.String(), "enrollment_token_hash") {
		t.Fatal("fleet inventory leaked enrollment or agent credential material")
	}

	heartbeat := contractLabJSON(t, map[string]string{
		"node_id": "rotation-node", "agent_version": fleetAgentVersion, "hostname": "rotation-node", "os_name": "Ubuntu", "os_version": "26.04", "architecture": "amd64",
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/fleet/heartbeat", strings.NewReader(heartbeat))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer definitely-invalid")
	rr = httptest.NewRecorder()
	app.handler.ServeHTTP(rr, req)
	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("invalid heartbeat bearer=%d body=%s", rr.Code, rr.Body.String())
	}

	rr = requestJSON(t, app.handler, http.MethodGet, "/api/v1/fleet/nodes", "", adminCookie, "")
	after := contractLabDecode[contractLabFleetInventory](t, rr.Body.Bytes())
	if len(after.Nodes) != 1 || after.Nodes[0].UpdatedAt != before.Nodes[0].UpdatedAt || after.Nodes[0].LastSeenAt != before.Nodes[0].LastSeenAt || after.Summary.Healthy != before.Summary.Healthy {
		t.Fatalf("failed heartbeat mutated authoritative Fleet state:\nbefore=%+v\nafter=%+v", before, after)
	}
}

func TestContractLabFleetBootstrapAssetsArePublicReadOnlyContract(t *testing.T) {
	app := newTestApp(t)
	paths := []struct {
		path        string
		contentType string
	}{
		{"/api/v1/fleet/agent/install.sh", "text/x-shellscript; charset=utf-8"},
		{"/api/v1/fleet/agent/agent.py", "text/x-python; charset=utf-8"},
	}
	var digest string
	for _, tc := range paths {
		rr := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodGet, tc.path, nil)
		app.handler.ServeHTTP(rr, req)
		if rr.Code != http.StatusOK {
			t.Fatalf("GET %s=%d body=%s", tc.path, rr.Code, rr.Body.String())
		}
		if rr.Header().Get("Content-Type") != tc.contentType || rr.Header().Get("Cache-Control") != "no-store" || rr.Header().Get("X-Content-Type-Options") != "nosniff" {
			t.Fatalf("asset response headers drifted for %s: %v", tc.path, rr.Header())
		}
		if rr.Header().Get("X-Control-Center-Fleet-Agent-Version") != fleetAgentVersion {
			t.Fatalf("asset version header drifted for %s", tc.path)
		}
		assetDigest := rr.Header().Get("X-Control-Center-Fleet-Agent-SHA256")
		if len(assetDigest) != 64 {
			t.Fatalf("invalid asset digest for %s: %q", tc.path, assetDigest)
		}
		if digest == "" {
			digest = assetDigest
		} else if assetDigest != digest {
			t.Fatalf("installer/source digest identity drift: first=%s current=%s", digest, assetDigest)
		}
		if rr.Header().Get("Set-Cookie") != "" {
			t.Fatalf("public bootstrap asset must not create a browser session: %s", tc.path)
		}

		rr = httptest.NewRecorder()
		req = httptest.NewRequest(http.MethodPost, tc.path, strings.NewReader("{}"))
		app.handler.ServeHTTP(rr, req)
		if rr.Code < 400 {
			t.Fatalf("POST %s unexpectedly served bootstrap content: status=%d", tc.path, rr.Code)
		}
		if rr.Header().Get("X-Control-Center-Fleet-Agent-Version") != "" || rr.Header().Get("X-Control-Center-Fleet-Agent-SHA256") != "" {
			t.Fatalf("non-GET %s must not be handled as a bootstrap asset", tc.path)
		}
	}
}

func TestContractLabRBACPermissionMatrixSelfProtectionAndSessionRevocation(t *testing.T) {
	app := newTestApp(t)
	adminCookie, adminCSRF := login(t, app, "admin", app.adminPassword)

	rr := requestJSON(t, app.handler, http.MethodPost, "/api/v1/rbac/users", `{"username":"rbaccontract","password":"rbaccontract-password-123","role":"viewer"}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusCreated {
		t.Fatalf("create viewer=%d body=%s", rr.Code, rr.Body.String())
	}
	viewerCookie, viewerCSRF := login(t, app, "rbaccontract", "rbaccontract-password-123")

	rr = requestJSON(t, app.handler, http.MethodGet, "/api/v1/rbac/users", "", viewerCookie, "")
	if rr.Code != http.StatusForbidden {
		t.Fatalf("viewer RBAC inventory=%d body=%s", rr.Code, rr.Body.String())
	}
	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/rbac/users", `{"username":"forbidden-user","password":"forbidden-user-password-123","role":"viewer"}`, viewerCookie, viewerCSRF)
	if rr.Code != http.StatusForbidden {
		t.Fatalf("viewer RBAC create=%d body=%s", rr.Code, rr.Body.String())
	}

	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/rbac/users/admin/blocked", `{"blocked":true}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusConflict || !strings.Contains(rr.Body.String(), "self_block_forbidden") {
		t.Fatalf("admin self-block protection=%d body=%s", rr.Code, rr.Body.String())
	}

	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/rbac/users/rbaccontract/blocked", `{"blocked":true}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusOK {
		t.Fatalf("block viewer=%d body=%s", rr.Code, rr.Body.String())
	}
	rr = requestJSON(t, app.handler, http.MethodGet, "/api/v1/auth/session", "", viewerCookie, "")
	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("blocked viewer session remained valid=%d body=%s", rr.Code, rr.Body.String())
	}

	rr = requestJSON(t, app.handler, http.MethodPost, "/api/v1/rbac/users/rbaccontract/blocked", `{"blocked":false}`, adminCookie, adminCSRF)
	if rr.Code != http.StatusOK {
		t.Fatalf("unblock viewer=%d body=%s", rr.Code, rr.Body.String())
	}
	viewerCookie, _ = login(t, app, "rbaccontract", "rbaccontract-password-123")
	rr = requestJSON(t, app.handler, http.MethodGet, "/api/v1/fleet/capabilities", "", viewerCookie, "")
	if rr.Code != http.StatusOK {
		t.Fatalf("unblocked viewer did not recover read capability=%d body=%s", rr.Code, rr.Body.String())
	}
}
