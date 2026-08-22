package observability

import (
	"testing"
	"time"
)

func TestAuditForOperationReturnsBoundedNewestFirstCorrelation(t *testing.T) {
	audit, err := OpenAudit(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}

	base := time.Date(2026, 8, 22, 12, 0, 0, 0, time.UTC)
	fixtures := []AuditEvent{
		{Time: base, OperationID: "op-target", Action: "rbac.user.create", Result: "success"},
		{Time: base.Add(time.Second), OperationID: "op-other", Action: "network.interfaces.read", Result: "success"},
		{Time: base.Add(2 * time.Second), OperationID: "op-target", Action: "operations.verify", Result: "success"},
	}
	for _, event := range fixtures {
		if err := audit.Append(event); err != nil {
			t.Fatal(err)
		}
	}

	events, err := audit.ForOperation(" op-target ", 1)
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 1 {
		t.Fatalf("len(events)=%d, want 1", len(events))
	}
	if events[0].OperationID != "op-target" || events[0].Action != "operations.verify" {
		t.Fatalf("unexpected correlation result: %+v", events[0])
	}

	missing, err := audit.ForOperation("op-missing", 100)
	if err != nil {
		t.Fatal(err)
	}
	if len(missing) != 0 {
		t.Fatalf("missing correlation returned %+v", missing)
	}

	blank, err := audit.ForOperation("   ", 100)
	if err != nil {
		t.Fatal(err)
	}
	if len(blank) != 0 {
		t.Fatalf("blank correlation returned %+v", blank)
	}
}
