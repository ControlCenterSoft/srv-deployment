package dns

import (
	"strings"
	"testing"
)

func TestPreflightResolverChangeCapturesStableSourceAndRecoverySteps(t *testing.T) {
	actual := ResolverState{
		Schema:              1,
		Source:              "/run/systemd/resolve/resolv.conf",
		SourceKind:          resolverSourceManagerSystemd,
		SourceMode:          resolverSourceModeSystemdStub,
		SourceManager:       resolverSourceManagerSystemd,
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
	if result.SourceMode != resolverSourceModeSystemdStub || result.SourceManager != resolverSourceManagerSystemd || result.SourceAmbiguous {
		t.Fatalf("unexpected source identity: %+v", result)
	}
	if !strings.HasPrefix(result.SourceFingerprint, "sha256:") || len(result.SourceFingerprint) != len("sha256:")+64 {
		t.Fatalf("source fingerprint=%q", result.SourceFingerprint)
	}
	if len(result.Blockers) != 0 || len(result.Warnings) != 0 || len(result.Checks) < 6 || len(result.RequiredExecutorSteps) != 4 {
		t.Fatalf("unexpected checks/blockers/warnings/steps: checks=%v blockers=%v warnings=%v steps=%v", result.Checks, result.Blockers, result.Warnings, result.RequiredExecutorSteps)
	}
	if len(result.Rollback.Nameservers) != 1 || result.Rollback.Nameservers[0] != "192.0.2.53" {
		t.Fatalf("rollback=%+v", result.Rollback)
	}
}

func TestPreflightResolverChangeReportsUnsupportedSourceAsBlocker(t *testing.T) {
	actual := ResolverState{
		Schema:          1,
		Source:          "/tmp/custom-resolver",
		SourceKind:      "custom",
		SourceMode:      resolverSourceModeExternalLink,
		SourceManager:   resolverSourceManagerUnknown,
		SourceAmbiguous: true,
		Nameservers:     []string{"192.0.2.53"},
		SearchDomains:   []string{"corp.example"},
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
	if len(result.Warnings) != 1 || result.Warnings[0] != "resolver_source_manager_ambiguous" {
		t.Fatalf("warnings=%v", result.Warnings)
	}
}

func TestPreflightResolverChangeRejectsMissingOrMalformedExpectedFingerprint(t *testing.T) {
	actual := ResolverState{
		Schema:          1,
		Source:          "/etc/resolv.conf",
		SourceKind:      "resolv_conf",
		SourceMode:      resolverSourceModeDirect,
		SourceManager:   resolverSourceManagerUnknown,
		SourceAmbiguous: true,
		Nameservers:     []string{"192.0.2.53"},
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
		Schema:          1,
		Source:          "/etc/resolv.conf",
		SourceKind:      "resolv_conf",
		SourceMode:      resolverSourceModeDirect,
		SourceManager:   resolverSourceManagerUnknown,
		SourceAmbiguous: true,
		Nameservers:     []string{"192.0.2.53"},
		SearchDomains:   []string{"corp.example"},
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

func TestPreflightResolverChangeWarnsOnAmbiguousManagerWithoutChangingPassContract(t *testing.T) {
	actual := ResolverState{
		Schema:          1,
		Source:          "/etc/resolv.conf",
		SourceKind:      "resolv_conf",
		SourceMode:      resolverSourceModeDirect,
		SourceManager:   resolverSourceManagerUnknown,
		SourceAmbiguous: true,
		Nameservers:     []string{"192.0.2.53"},
	}
	result, err := PreflightResolverChange(ResolverPreflightRequest{
		Nameservers:               []string{"198.51.100.53"},
		ExpectedSourceFingerprint: ResolverStateFingerprint(actual),
	}, actual)
	if err != nil {
		t.Fatal(err)
	}
	if !result.Passed {
		t.Fatalf("manager ambiguity unexpectedly changed existing preflight pass contract: %+v", result)
	}
	if len(result.Warnings) != 1 || result.Warnings[0] != "resolver_source_manager_ambiguous" {
		t.Fatalf("warnings=%v", result.Warnings)
	}
}

func TestPreflightResolverChangeWarnsWhenLocalStubUpstreamIsUnresolved(t *testing.T) {
	actual := ResolverState{
		Schema:          1,
		Source:          networkManagerResolvConfPath,
		SourceKind:      "resolv_conf",
		SourceMode:      resolverSourceModeNetworkManager,
		SourceManager:   resolverSourceManagerNetworkManager,
		SourceAmbiguous: false,
		StubDetected:    true,
		Nameservers:     []string{"127.0.0.1"},
	}
	result, err := PreflightResolverChange(ResolverPreflightRequest{
		Nameservers:               []string{"192.0.2.53"},
		ExpectedSourceFingerprint: ResolverStateFingerprint(actual),
	}, actual)
	if err != nil {
		t.Fatal(err)
	}
	if !result.Passed || len(result.Warnings) != 1 || result.Warnings[0] != "resolver_local_stub_upstream_unresolved" {
		t.Fatalf("unexpected result: %+v", result)
	}
}

func TestResolverStateFingerprintChangesWithAuthoritativeState(t *testing.T) {
	base := ResolverState{
		Schema:          1,
		Source:          "/etc/resolv.conf",
		SourceKind:      "resolv_conf",
		SourceMode:      resolverSourceModeDirect,
		SourceManager:   resolverSourceManagerUnknown,
		SourceAmbiguous: true,
		Nameservers:     []string{"192.0.2.53"},
		SearchDomains:   []string{"corp.example"},
		Options:         []string{"edns0"},
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

func TestResolverStateFingerprintChangesWithSourceOwnershipEvidence(t *testing.T) {
	base := ResolverState{
		Schema:          1,
		Source:          "/etc/resolv.conf",
		SourceKind:      "resolv_conf",
		SourceMode:      resolverSourceModeDirect,
		SourceManager:   resolverSourceManagerUnknown,
		SourceAmbiguous: true,
		Nameservers:     []string{"192.0.2.53"},
	}
	fingerprint := ResolverStateFingerprint(base)

	changed := base
	changed.SourceMode = resolverSourceModeNetworkManager
	changed.SourceManager = resolverSourceManagerNetworkManager
	changed.SourceAmbiguous = false
	changed.EtcResolvConfTarget = networkManagerResolvConfPath
	if fingerprint == ResolverStateFingerprint(changed) {
		t.Fatal("fingerprint did not change when source ownership evidence changed")
	}
}
