package dns

import "testing"

func TestPreviewResolverChangeCarriesSourceOwnershipEvidence(t *testing.T) {
	actual := ResolverState{
		Schema:          1,
		Source:          "/etc/resolv.conf",
		SourceKind:      "resolv_conf",
		SourceMode:      resolverSourceModeDirect,
		SourceManager:   resolverSourceManagerUnknown,
		SourceAmbiguous: true,
		Nameservers:     []string{"192.0.2.53"},
	}
	plan, err := PreviewResolverChange(ResolverChangeRequest{Nameservers: []string{"198.51.100.53"}}, actual)
	if err != nil {
		t.Fatal(err)
	}
	if plan.SourceMode != actual.SourceMode || plan.SourceManager != actual.SourceManager || !plan.SourceAmbiguous {
		t.Fatalf("source evidence not carried: %+v", plan)
	}
	if len(plan.Warnings) != 1 || plan.Warnings[0] != "resolver_source_manager_ambiguous" {
		t.Fatalf("warnings=%v", plan.Warnings)
	}
}
