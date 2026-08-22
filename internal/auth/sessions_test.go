package auth

import (
	"testing"
	"time"

	"github.com/ControlCenterSoft/srv-deployment/internal/state"
)

func TestRevokeOtherSessionsKeepsCurrentAndOtherUsers(t *testing.T) {
	manager := NewManager(time.Hour)
	alice := state.User{Username: "alice", Role: state.RoleAdmin}
	bob := state.User{Username: "bob", Role: state.RoleViewer}

	aliceOld1, _, err := manager.Create(alice)
	if err != nil {
		t.Fatal(err)
	}
	aliceOld2, _, err := manager.Create(alice)
	if err != nil {
		t.Fatal(err)
	}
	aliceCurrent, _, err := manager.Create(alice)
	if err != nil {
		t.Fatal(err)
	}
	bobToken, _, err := manager.Create(bob)
	if err != nil {
		t.Fatal(err)
	}

	revoked, ok := manager.RevokeOtherSessions(alice.Username, aliceCurrent)
	if !ok || revoked != 2 {
		t.Fatalf("revoked=%d ok=%v, want revoked=2 ok=true", revoked, ok)
	}
	if _, ok := manager.Lookup(aliceCurrent); !ok {
		t.Fatal("current session was revoked")
	}
	if _, ok := manager.Lookup(aliceOld1); ok {
		t.Fatal("first old session is still active")
	}
	if _, ok := manager.Lookup(aliceOld2); ok {
		t.Fatal("second old session is still active")
	}
	if _, ok := manager.Lookup(bobToken); !ok {
		t.Fatal("another user's session was revoked")
	}
}

func TestRevokeOtherSessionsFailsClosedForInvalidOrForeignCurrentToken(t *testing.T) {
	manager := NewManager(time.Hour)
	alice := state.User{Username: "alice", Role: state.RoleAdmin}
	bob := state.User{Username: "bob", Role: state.RoleViewer}

	aliceToken, _, err := manager.Create(alice)
	if err != nil {
		t.Fatal(err)
	}
	bobToken, _, err := manager.Create(bob)
	if err != nil {
		t.Fatal(err)
	}

	if revoked, ok := manager.RevokeOtherSessions(alice.Username, "not-a-session-token"); ok || revoked != 0 {
		t.Fatalf("invalid current token revoked=%d ok=%v", revoked, ok)
	}
	if revoked, ok := manager.RevokeOtherSessions(alice.Username, bobToken); ok || revoked != 0 {
		t.Fatalf("foreign current token revoked=%d ok=%v", revoked, ok)
	}
	if _, ok := manager.Lookup(aliceToken); !ok {
		t.Fatal("valid alice session changed after rejected request")
	}
	if _, ok := manager.Lookup(bobToken); !ok {
		t.Fatal("valid bob session changed after rejected request")
	}
}
