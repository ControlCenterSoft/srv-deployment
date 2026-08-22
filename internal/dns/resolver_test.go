package dns

import (
	"os"
	"path/filepath"
	"testing"
)

func TestInventoryUsesDirectResolvConfWithoutStub(t *testing.T) {
	root := t.TempDir()
	etcPath := filepath.Join(root, "resolv.conf")
	resolvedPath := filepath.Join(root, "resolved.conf")
	if err := os.WriteFile(etcPath, []byte("nameserver 192.0.2.53\nsearch corp.example lab.example\noptions edns0 trust-ad\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(resolvedPath, []byte("nameserver 198.51.100.53\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	state, err := inventoryFromPaths(etcPath, resolvedPath)
	if err != nil {
		t.Fatal(err)
	}
	if state.Schema != 1 || state.Managed || state.ApplySupported {
		t.Fatalf("unexpected management contract: %+v", state)
	}
	if state.Source != etcPath || state.SourceKind != "resolv_conf" || state.StubDetected {
		t.Fatalf("unexpected source: %+v", state)
	}
	if state.SourceMode != resolverSourceModeDirect || state.SourceManager != resolverSourceManagerUnknown || !state.SourceAmbiguous {
		t.Fatalf("unexpected source identity: %+v", state)
	}
	if len(state.Nameservers) != 1 || state.Nameservers[0] != "192.0.2.53" {
		t.Fatalf("nameservers=%v", state.Nameservers)
	}
	if len(state.SearchDomains) != 2 || state.SearchDomains[0] != "corp.example" || state.SearchDomains[1] != "lab.example" {
		t.Fatalf("search=%v", state.SearchDomains)
	}
	if len(state.Options) != 2 {
		t.Fatalf("options=%v", state.Options)
	}
}

func TestInventoryResolvesSystemdStubToUpstreamState(t *testing.T) {
	root := t.TempDir()
	actualEtc := filepath.Join(root, "stub-resolv.conf")
	etcPath := filepath.Join(root, "resolv.conf")
	resolvedPath := filepath.Join(root, "resolved.conf")
	if err := os.WriteFile(actualEtc, []byte("nameserver 127.0.0.53\nsearch local\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(actualEtc, etcPath); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(resolvedPath, []byte("nameserver 203.0.113.53\nnameserver 2001:db8::53\nsearch example.test\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	state, err := inventoryFromPaths(etcPath, resolvedPath)
	if err != nil {
		t.Fatal(err)
	}
	if !state.StubDetected || state.Source != resolvedPath || state.SourceKind != resolverSourceManagerSystemd {
		t.Fatalf("unexpected resolved source: %+v", state)
	}
	if state.SourceMode != resolverSourceModeSystemdStub || state.SourceManager != resolverSourceManagerSystemd || state.SourceAmbiguous {
		t.Fatalf("unexpected source identity: %+v", state)
	}
	if state.EtcResolvConfTarget != actualEtc {
		t.Fatalf("target=%q", state.EtcResolvConfTarget)
	}
	if len(state.Nameservers) != 2 || state.Nameservers[0] != "203.0.113.53" || state.Nameservers[1] != "2001:db8::53" {
		t.Fatalf("nameservers=%v", state.Nameservers)
	}
	if len(state.SearchDomains) != 1 || state.SearchDomains[0] != "example.test" {
		t.Fatalf("search=%v", state.SearchDomains)
	}
}

func TestInventoryDoesNotAssumeSystemdForUnownedLoopbackResolver(t *testing.T) {
	root := t.TempDir()
	etcPath := filepath.Join(root, "resolv.conf")
	resolvedPath := filepath.Join(root, "resolved.conf")
	if err := os.WriteFile(etcPath, []byte("nameserver 127.0.0.1\nsearch local\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(resolvedPath, []byte("nameserver 198.51.100.53\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	state, err := inventoryFromPaths(etcPath, resolvedPath)
	if err != nil {
		t.Fatal(err)
	}
	if !state.StubDetected || state.SourceKind != "resolv_conf" || state.Source != etcPath {
		t.Fatalf("unowned loopback source was misclassified: %+v", state)
	}
	if len(state.Nameservers) != 1 || state.Nameservers[0] != "127.0.0.1" {
		t.Fatalf("unexpected effective nameservers=%v", state.Nameservers)
	}
	warnings := resolverSourceWarnings(state)
	if len(warnings) != 2 || warnings[0] != "resolver_source_manager_ambiguous" || warnings[1] != "resolver_local_stub_upstream_unresolved" {
		t.Fatalf("warnings=%v", warnings)
	}
}

func TestInventoryRecognizesSystemdUplinkSymlink(t *testing.T) {
	root := t.TempDir()
	etcPath := filepath.Join(root, "resolv.conf")
	resolvedPath := filepath.Join(root, "resolved.conf")
	if err := os.WriteFile(resolvedPath, []byte("nameserver 203.0.113.53\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(resolvedPath, etcPath); err != nil {
		t.Fatal(err)
	}

	state, err := inventoryFromPaths(etcPath, resolvedPath)
	if err != nil {
		t.Fatal(err)
	}
	if state.SourceMode != resolverSourceModeSystemdUplink || state.SourceManager != resolverSourceManagerSystemd || state.SourceAmbiguous {
		t.Fatalf("unexpected source identity: %+v", state)
	}
	if state.SourceKind != resolverSourceManagerSystemd || state.Source != resolvedPath {
		t.Fatalf("unexpected effective source: %+v", state)
	}
}

func TestClassifyResolverLinkTargetRecognizesKnownManagersAndUnknownLinks(t *testing.T) {
	tests := []struct {
		name      string
		target    string
		mode      string
		manager   string
		ambiguous bool
	}{
		{name: "systemd stub", target: systemdStubResolvConfPath, mode: resolverSourceModeSystemdStub, manager: resolverSourceManagerSystemd},
		{name: "systemd uplink", target: resolvedConfPath, mode: resolverSourceModeSystemdUplink, manager: resolverSourceManagerSystemd},
		{name: "systemd static", target: "/usr/lib/systemd/resolv.conf", mode: resolverSourceModeSystemdStatic, manager: resolverSourceManagerSystemd},
		{name: "network manager runtime", target: networkManagerResolvConfPath, mode: resolverSourceModeNetworkManager, manager: resolverSourceManagerNetworkManager},
		{name: "unknown link", target: "/run/custom/resolv.conf", mode: resolverSourceModeExternalLink, manager: resolverSourceManagerUnknown, ambiguous: true},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			mode, manager, ambiguous := classifyResolverLinkTarget(tc.target, resolvedConfPath)
			if mode != tc.mode || manager != tc.manager || ambiguous != tc.ambiguous {
				t.Fatalf("got mode=%q manager=%q ambiguous=%t", mode, manager, ambiguous)
			}
		})
	}
}

func TestNormalizeResolverLinkTargetResolvesRelativeTarget(t *testing.T) {
	got := normalizeResolverLinkTarget("/etc/resolv.conf", "../run/systemd/resolve/stub-resolv.conf")
	if got != systemdStubResolvConfPath {
		t.Fatalf("target=%q", got)
	}
}

func TestParseResolverContentRejectsInvalidNameserver(t *testing.T) {
	if _, err := parseResolverContent("nameserver not-an-ip\n"); err == nil {
		t.Fatal("expected invalid nameserver rejection")
	}
}

func TestParseResolverContentDeduplicatesAndBoundsTokens(t *testing.T) {
	state, err := parseResolverContent("nameserver 192.0.2.53\nnameserver 192.0.2.53\nsearch example.test example.test\noptions edns0 edns0\n")
	if err != nil {
		t.Fatal(err)
	}
	if len(state.Nameservers) != 1 || len(state.SearchDomains) != 1 || len(state.Options) != 1 {
		t.Fatalf("unexpected duplicate state: %+v", state)
	}
}
