package dns

import (
	"strings"
	"testing"
)

func TestPreflightResolverChangeCapturesStableSourceAndRecoverySteps(t *testing.T) {
	actual := ResolverState{
		Schema:              1,
		Source:              "/run/systemd/resolve/resolv.conf",
		SourceKind:          "systemd_resolved",
		EtcResolvConfTarget: "../run/systemd/resolve/stub-resolv.conf",
		StubDetected:        true,
		Nameservers:         []string{"192.0.2.53"},
		SearchDomains:       []string{"corp.example"},
		Options:             []string{"edns0"},
	}
	result, err := PreflightResolverChange(ResolverChangeRequest{
		Nameservers:   []string{"198.51.100.53", "2001:db8::53"},
		SearchDomains: []string{"example.test"},
	}, actual)
	if err != nil {
		t.Fatal(err)
	}
	if result.Schema != 1 || !result.Passed || result.ApplySupported || result.NoOp {
		t.Fatalf("unexpected preflight flags: %+v", result)
	}
	if !strings.HasPrefix(result.SourceFingerprint, "sha256:") || len(result.SourceFingerprint) != len("sha256:")+64 {
		t.Fatalf("source fingerprint=%q", result.SourceFingerprint)
	}
	if len(result.Blockers) != 0 || len(result.Checks) < 5 || len(result.RequiredExecutorSteps) != 4 {
		t.Fatalf("unexpected checks/blockers/steps: checks=%v blockers=%v steps=%v", result.Checks, result.Blockers, result.RequiredExecutorSteps)
	}
	if len(result.Rollback.Nameservers) != 1 || result.Rollback.Nameservers[0] != "192.0.2.53" {
		t.Fatalf("rollback=%+v", result.Rollback)
	}
}

func TestPreflightResolverChangeReportsUnsupportedSourceAsBlocker(t *testing.T) {
	actual := ResolverState{
		Schema:        1,
		Source:        "/tmp/custom-resolver",
		SourceKind:    "custom",
		Nameservers:   []string{"192.0.2.53"},
		SearchDomains: []string{"corp.example"},
	}
	result, err := PreflightResolverChange(ResolverChangeRequest{
		Nameservers:   []string{"192.0.2.53"},
		SearchDomains: []string{"corp.example"},
	}, actual)
	if err != nil {
		t.Fatal(err)
	}
	if result.Passed || len(result.Blockers) != 1 || result.Blockers[0] != "resolver_source_supported" {
		t.Fatalf("unexpected unsupported-source result: %+v", result)
	}
}

func TestResolverStateFingerprintChangesWithAuthoritativeState(t *testing.T) {
	base := ResolverState{
		Schema:        1,
		Source:        "/etc/resolv.conf",
		SourceKind:    "resolv_conf",
		Nameservers:   []string{"192.0.2.53"},
		SearchDomains: []string{"corp.example"},
		Options:       []string{"edns0"},
	}
	first := ResolverStateFingerprint(base)
	second := ResolverStateFingerprint(base)
	if first == "" || first != second {
		t.Fatalf("fingerprint is not deterministic: first=%q second=%q", first, second)
	}
	changed := base
	changed.Nameservers = []string{"198.51.100.53"}
	if first == ResolverStateFingerprint(changed) {
		t.Fatal("fingerprint did not change with resolver state")
	}
}
