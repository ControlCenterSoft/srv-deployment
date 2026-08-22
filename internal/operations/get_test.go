package operations

import "testing"

func TestGetReturnsExactRecordWithoutMutation(t *testing.T) {
	s, err := Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	started, err := s.Start("op-detail-1", "rbac.user.create", "admin", "admin", "viewer")
	if err != nil {
		t.Fatal(err)
	}

	got, ok := s.Get(started.ID)
	if !ok {
		t.Fatal("expected operation lookup to succeed")
	}
	if got.ID != started.ID || got.Kind != started.Kind || got.Status != StatusRunning {
		t.Fatalf("unexpected operation: %+v", got)
	}
	if s.Count() != 1 {
		t.Fatalf("lookup mutated operation count: %d", s.Count())
	}
	if _, ok := s.Get("missing-operation"); ok {
		t.Fatal("unexpected missing operation lookup success")
	}
	if _, ok := s.Get(""); ok {
		t.Fatal("empty identifier must not resolve")
	}
}
