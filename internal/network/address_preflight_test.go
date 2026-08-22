package network

import "testing"

func TestPreflightAddressChangePassesWithStableSource(t *testing.T) {
	interfaces := []Interface{{Name: "eth0", Index: 2, MTU: 1500, HardwareAddress: "02:00:00:00:00:01", Flags: []string{"broadcast", "up"}, Addresses: []string{"192.0.2.10/24"}}}
	fingerprint := InterfaceFingerprintForName(interfaces, "eth0")
	result, err := PreflightAddressChange(AddressPreflightRequest{Interface: "eth0", CIDR: "192.0.2.20/24", ExpectedSourceFingerprint: fingerprint}, interfaces)
	if err != nil {
		t.Fatal(err)
	}
	if !result.Passed {
		t.Fatalf("blockers=%v checks=%v", result.Blockers, result.Checks)
	}
	if result.ApplySupported {
		t.Fatal("preflight must not enable apply")
	}
	if result.SourceFingerprint != fingerprint {
		t.Fatalf("fingerprint=%q want=%q", result.SourceFingerprint, fingerprint)
	}
	if len(result.RequiredExecutorSteps) < 5 {
		t.Fatalf("executor steps=%v", result.RequiredExecutorSteps)
	}
}

func TestPreflightAddressChangeBlocksStaleSource(t *testing.T) {
	before := []Interface{{Name: "eth0", Index: 2, MTU: 1500, HardwareAddress: "02:00:00:00:00:01", Flags: []string{"up"}, Addresses: []string{"192.0.2.10/24"}}}
	expected := InterfaceFingerprintForName(before, "eth0")
	after := []Interface{{Name: "eth0", Index: 2, MTU: 1500, HardwareAddress: "02:00:00:00:00:01", Flags: []string{"up"}, Addresses: []string{"192.0.2.11/24"}}}
	result, err := PreflightAddressChange(AddressPreflightRequest{Interface: "eth0", CIDR: "192.0.2.20/24", ExpectedSourceFingerprint: expected}, after)
	if err != nil {
		t.Fatal(err)
	}
	if result.Passed {
		t.Fatal("stale source must block preflight")
	}
	found := false
	for _, blocker := range result.Blockers {
		if blocker == "interface_source_unchanged" {
			found = true
		}
	}
	if !found {
		t.Fatalf("blockers=%v", result.Blockers)
	}
}

func TestInterfaceFingerprintCanonicalAndSensitiveToIdentity(t *testing.T) {
	a := Interface{Name: "eth0", Index: 2, MTU: 1500, HardwareAddress: "AA:BB:CC:DD:EE:FF", Flags: []string{"up", "broadcast"}, Addresses: []string{"2001:db8::1/64", "192.0.2.10/24"}}
	b := Interface{Name: "eth0", Index: 2, MTU: 1500, HardwareAddress: "aa:bb:cc:dd:ee:ff", Flags: []string{"broadcast", "up"}, Addresses: []string{"192.0.2.10/24", "2001:db8::1/64"}}
	if InterfaceFingerprint(a) != InterfaceFingerprint(b) {
		t.Fatal("ordering/case normalization should not change fingerprint")
	}
	b.Index = 3
	if InterfaceFingerprint(a) == InterfaceFingerprint(b) {
		t.Fatal("interface identity change must change fingerprint")
	}
}

func TestPreflightAddressChangeRejectsMalformedFingerprint(t *testing.T) {
	interfaces := []Interface{{Name: "eth0", Index: 2, MTU: 1500, Flags: []string{"up"}, Addresses: []string{"192.0.2.10/24"}}}
	if _, err := PreflightAddressChange(AddressPreflightRequest{Interface: "eth0", CIDR: "192.0.2.20/24", ExpectedSourceFingerprint: "sha256:not-valid"}, interfaces); err == nil {
		t.Fatal("expected malformed fingerprint rejection")
	}
}

func TestPreflightAddressChangeAllowsEmptyRollbackState(t *testing.T) {
	interfaces := []Interface{{Name: "eth0", Index: 2, MTU: 1500, Flags: []string{"up"}, Addresses: []string{}}}
	fingerprint := InterfaceFingerprintForName(interfaces, "eth0")
	result, err := PreflightAddressChange(AddressPreflightRequest{Interface: "eth0", CIDR: "192.0.2.20/24", ExpectedSourceFingerprint: fingerprint}, interfaces)
	if err != nil {
		t.Fatal(err)
	}
	if !result.Passed {
		t.Fatalf("empty rollback is valid captured state; blockers=%v", result.Blockers)
	}
	if result.RollbackAddresses == nil || len(result.RollbackAddresses) != 0 {
		t.Fatalf("rollback=%#v", result.RollbackAddresses)
	}
}
