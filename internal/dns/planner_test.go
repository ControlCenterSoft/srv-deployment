package dns

import "testing"

func TestPreviewResolverChangeBuildsDesiredActualAndRollback(t *testing.T) {
	actual := ResolverState{
		SourceKind:    "systemd_resolved",
		Nameservers:   []string{"192.0.2.53"},
		SearchDomains: []string{"corp.example"},
		Options:       []string{"edns0", "trust-ad"},
	}
	plan, err := PreviewResolverChange(ResolverChangeRequest{
		Nameservers:   []string{" 198.51.100.53 ", "198.51.100.53", "2001:db8::53"},
		SearchDomains: []string{" Example.Test. ", "example.test"},
	}, actual)
	if err != nil {
		t.Fatal(err)
	}
	if plan.Schema != 1 || plan.ApplySupported || plan.NoOp {
		t.Fatalf("unexpected plan flags: %+v", plan)
	}
	if plan.SourceKind != "systemd_resolved" {
		t.Fatalf("source kind=%q", plan.SourceKind)
	}
	if len(plan.Desired.Nameservers) != 2 || plan.Desired.Nameservers[0] != "198.51.100.53" || plan.Desired.Nameservers[1] != "2001:db8::53" {
		t.Fatalf("desired nameservers=%v", plan.Desired.Nameservers)
	}
	if len(plan.Desired.SearchDomains) != 1 || plan.Desired.SearchDomains[0] != "example.test" {
		t.Fatalf("desired search=%v", plan.Desired.SearchDomains)
	}
	if len(plan.Desired.Options) != 2 || plan.Desired.Options[0] != "edns0" || plan.Desired.Options[1] != "trust-ad" {
		t.Fatalf("desired options=%v", plan.Desired.Options)
	}
	if len(plan.Rollback.Nameservers) != 1 || plan.Rollback.Nameservers[0] != "192.0.2.53" {
		t.Fatalf("rollback=%+v", plan.Rollback)
	}
	if len(plan.Preconditions) < 4 {
		t.Fatalf("preconditions=%v", plan.Preconditions)
	}
}

func TestPreviewResolverChangeDetectsNoOp(t *testing.T) {
	actual := ResolverState{
		SourceKind:    "resolv_conf",
		Nameservers:   []string{"192.0.2.53"},
		SearchDomains: []string{"corp.example"},
		Options:       []string{"edns0"},
	}
	plan, err := PreviewResolverChange(ResolverChangeRequest{
		Nameservers:   []string{"192.0.2.53"},
		SearchDomains: []string{"corp.example"},
	}, actual)
	if err != nil {
		t.Fatal(err)
	}
	if !plan.NoOp {
		t.Fatalf("expected no-op plan: %+v", plan)
	}
}

func TestPreviewResolverChangeDetectsSemanticSearchDomainNoOp(t *testing.T) {
	actual := ResolverState{
		SourceKind:    "resolv_conf",
		Nameservers:   []string{"192.0.2.53"},
		SearchDomains: []string{"Corp.Example."},
		Options:       []string{"edns0"},
	}
	plan, err := PreviewResolverChange(ResolverChangeRequest{
		Nameservers:   []string{"192.0.2.53"},
		SearchDomains: []string{"corp.example"},
	}, actual)
	if err != nil {
		t.Fatal(err)
	}
	if !plan.NoOp {
		t.Fatalf("expected semantically equivalent DNS search domain to be a no-op: actual=%v desired=%v", plan.Actual.SearchDomains, plan.Desired.SearchDomains)
	}
	if len(plan.Actual.SearchDomains) != 1 || plan.Actual.SearchDomains[0] != "Corp.Example." {
		t.Fatalf("authoritative actual search representation changed: %v", plan.Actual.SearchDomains)
	}
	if len(plan.Rollback.SearchDomains) != 1 || plan.Rollback.SearchDomains[0] != "Corp.Example." {
		t.Fatalf("rollback search representation changed: %v", plan.Rollback.SearchDomains)
	}
}

func TestPreviewResolverChangeRejectsUnsafeInputs(t *testing.T) {
	actual := ResolverState{SourceKind: "resolv_conf", Nameservers: []string{"192.0.2.53"}}
	cases := []ResolverChangeRequest{
		{},
		{Nameservers: []string{"not-an-ip"}},
		{Nameservers: []string{"0.0.0.0"}},
		{Nameservers: []string{"224.0.0.1"}},
		{Nameservers: []string{"192.0.2.53"}, SearchDomains: []string{"bad/domain"}},
		{Nameservers: []string{"192.0.2.53"}, SearchDomains: []string{"-bad.example"}},
	}
	for i, in := range cases {
		if _, err := PreviewResolverChange(in, actual); err == nil {
			t.Fatalf("case %d expected validation error", i)
		}
	}
}
