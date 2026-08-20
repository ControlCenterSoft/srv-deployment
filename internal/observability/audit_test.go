package observability

import "testing"

func TestAuditAppendAndRecent(t *testing.T) {
	a, err := OpenAudit(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	if err := a.Append(AuditEvent{OperationID: "op-1", Actor: "admin", Role: "admin", Action: "rbac.user.create", Target: "viewer", Result: "success"}); err != nil {
		t.Fatal(err)
	}
	if err := a.Append(AuditEvent{OperationID: "op-2", Action: "auth.login", Result: "failed", ErrorCode: "invalid_credentials"}); err != nil {
		t.Fatal(err)
	}
	events, err := a.Recent(10)
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 2 || events[0].OperationID != "op-2" || events[1].OperationID != "op-1" {
		t.Fatalf("unexpected events: %+v", events)
	}
}
