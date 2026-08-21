package network

import "testing"

func TestPreviewAddressChangeBuildsRollbackPlan(t *testing.T) {
	interfaces := []Interface{{Name: "eth0", Index: 2, MTU: 1500, Flags: []string{"up", "broadcast"}, Addresses: []string{"192.0.2.10/24"}}}
	plan, err := PreviewAddressChange(AddressChangeRequest{Interface: "eth0", CIDR: "192.0.2.20/24"}, interfaces)
	if err != nil {
		t.Fatal(err)
	}
	if plan.Validation != "passed" {
		t.Fatalf("validation=%q", plan.Validation)
	}
	if plan.ApplySupported {
		t.Fatal("preview must never apply network configuration")
	}
	if !plan.RequiresRecoveryPath {
		t.Fatal("network change must require recovery path")
	}
	if len(plan.RollbackAddresses) != 1 || plan.RollbackAddresses[0] != "192.0.2.10/24" {
		t.Fatalf("rollback=%v", plan.RollbackAddresses)
	}
	if plan.NoOp {
		t.Fatal("different address must not be no-op")
	}
}

func TestPreviewAddressChangeRejectsLoopbackAndInvalidCIDR(t *testing.T) {
	interfaces := []Interface{{Name: "lo", Index: 1, MTU: 65536, Flags: []string{"up", "loopback"}, Addresses: []string{"127.0.0.1/8"}}}
	if _, err := PreviewAddressChange(AddressChangeRequest{Interface: "lo", CIDR: "127.0.0.2/8"}, interfaces); err == nil {
		t.Fatal("expected loopback rejection")
	}
	if _, err := PreviewAddressChange(AddressChangeRequest{Interface: "eth0", CIDR: "not-a-cidr"}, interfaces); err == nil {
		t.Fatal("expected CIDR rejection")
	}
}

func TestPreviewAddressChangeRecognizesNoOp(t *testing.T) {
	interfaces := []Interface{{Name: "eth0", Index: 2, MTU: 1500, Flags: []string{"up"}, Addresses: []string{"10.0.0.5/24"}}}
	plan, err := PreviewAddressChange(AddressChangeRequest{Interface: "eth0", CIDR: "10.0.0.5/24"}, interfaces)
	if err != nil {
		t.Fatal(err)
	}
	if !plan.NoOp {
		t.Fatal("same address must be no-op")
	}
}
