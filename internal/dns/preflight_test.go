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
	result, err := PreflightResolverChange(ResolverPreflightRequest{
		Nameservers:               []string{"198.51.100.53", "2001:db8::53"},
		SearchDomains:             []string{"example.test"},
		ExpectedSourceFingerprint: ResolverStateFingerprint(actual),
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
	if len(result.Blockers) != 0 || len(result.Checks) < 6 || len(result.RequiredExecutorSteps) != 4 {
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
	result, err := PreflightResolverChange(ResolverPreflightRequest{
		Nameservers:               []string{"192.0.2.53"},
		SearchDomains:             []string{"corp.example"},
		ExpectedSourceFingerprint: ResolverStateFingerprint(actual),
	}, actual)
	if err != nil {
		t.Fatal(err)
	}
	if result.Passed || len(result.Blockers) != 1 || result.Blockers[0] != "resolver_source_supported" {
		t.Fatalf("unexpected unsupported-source result: %+v", result)
	}
}

func TestPreflightResolverChangeRejectsMissingOrMalformedExpectedFingerprint(t *testing.T) {
	actual := ResolverState{
		Schema:      1,
		Source:      "/etc/resolv.conf",
		SourceKind:  "resolv_conf",
		Nameservers: []string{"192.0.2.53"},
	}
	for _, fingerprint := range []string{"", "sha256:bad", "md5:0123456789abcdef"} {
		_, err := PreflightResolverChange(ResolverPreflightRequest{
			Nameservers:               []string{"192.0.2.53"},
			ExpectedSourceFingerprint: fingerprint,
		}, actual)
		if err == nil {
			t.Fatalf("fingerprint %q was accepted", fingerprint)
		}
	}
}

func TestPreflightResolverChangeDetectsStalePreviewFingerprint(t *testing.T) {
	previewed := ResolverState{
		Schema:        1,
		Source:        "/etc/resolv.conf",
		SourceKind:    "resolv_conf",
		Nameservers:   []string{"192.0.2.53"},
		SearchDomains: []string{"corp.example"},
	}
	current := previewed
	current.Nameservers = []string{"198.51.100.53"}
	result, err := PreflightResolverChange(ResolverPreflightRequest{
		Nameservers:               []string{"203.0.113.53"},
		SearchDomains:             []string{"corp.example"},
		ExpectedSourceFingerprint: ResolverStateFingerprint(previewed),
	}, current)
	if err != nil {
		t.Fatal(err)
	}
	if result.Passed {
		t.Fatalf("stale preview unexpectedly passed: %+v", result)
	}
	found := false
	for _, blocker := range result.Blockers {
		if blocker == "resolver_source_unchanged" {
			found = true
		}
	}
	if !found {
		t.Fatalf("missing stale-source blocker: %+v", result.Blockers)
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
