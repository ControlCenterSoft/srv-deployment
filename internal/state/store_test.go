package state

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestBootstrapPersistsSeparateSecrets(t *testing.T) {
	dir := t.TempDir()
	s, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	password, created, err := s.BootstrapAdmin("Admin")
	if err != nil || !created {
		t.Fatalf("created=%v err=%v", created, err)
	}
	stateBytes, _ := os.ReadFile(filepath.Join(dir, "state.json"))
	if strings.Contains(string(stateBytes), password) || strings.Contains(string(stateBytes), "pbkdf2-sha256") {
		t.Fatal("state metadata contains password material")
	}
	secretBytes, _ := os.ReadFile(filepath.Join(dir, "secrets.json"))
	if !strings.Contains(string(secretBytes), "pbkdf2-sha256") {
		t.Fatal("password hash not stored in secrets")
	}
	reopened, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := reopened.VerifyCredentials("admin", password); !ok {
		t.Fatal("persisted credentials failed")
	}
}

func TestPasswordChangeRemovesBootstrapSecret(t *testing.T) {
	dir := t.TempDir()
	s, _ := Open(dir)
	old, _, _ := s.BootstrapAdmin("admin")
	if err := s.ChangePassword("admin", old, "replacement-password-123"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(dir, "bootstrap-admin.secret")); !os.IsNotExist(err) {
		t.Fatal("bootstrap secret remains after password change")
	}
	if _, ok := s.VerifyCredentials("admin", old); ok {
		t.Fatal("old password still works")
	}
	if _, ok := s.VerifyCredentials("admin", "replacement-password-123"); !ok {
		t.Fatal("new password does not work")
	}
}

func TestCannotBlockLastActiveAdmin(t *testing.T) {
	s, _ := Open(t.TempDir())
	_, _, _ = s.BootstrapAdmin("admin")
	if _, err := s.SetBlocked("admin", true); err == nil {
		t.Fatal("expected last-admin protection")
	}
}

func TestPasswordHashUsesConfiguredKDF(t *testing.T) {
	h, err := HashPassword("correct-horse-battery-staple")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(h, "$pbkdf2-sha256$i=600000$") {
		t.Fatalf("unexpected hash format %q", h)
	}
	if !VerifyPassword("correct-horse-battery-staple", h) || VerifyPassword("wrong-password", h) {
		t.Fatal("password verification mismatch")
	}
}

func TestRevisionMismatchFailsClosed(t *testing.T) {
	dir := t.TempDir()
	s, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := s.BootstrapAdmin("admin"); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "secrets.json")
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var doc map[string]any
	if err := json.Unmarshal(b, &doc); err != nil {
		t.Fatal(err)
	}
	doc["revision"] = doc["revision"].(float64) + 1
	b, _ = json.MarshalIndent(doc, "", "  ")
	if err := os.WriteFile(path, append(b, '\n'), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := Open(dir); err == nil || !strings.Contains(err.Error(), "revision mismatch") {
		t.Fatalf("expected revision mismatch, got %v", err)
	}
}

func TestUnsupportedSchemaFailsClosed(t *testing.T) {
	dir := t.TempDir()
	s, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := s.BootstrapAdmin("admin"); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"state.json", "secrets.json"} {
		path := filepath.Join(dir, name)
		b, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		var doc map[string]any
		if err := json.Unmarshal(b, &doc); err != nil {
			t.Fatal(err)
		}
		doc["schema"] = 99
		b, _ = json.MarshalIndent(doc, "", "  ")
		if err := os.WriteFile(path, append(b, '\n'), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := Open(dir); err == nil || !strings.Contains(err.Error(), "unsupported state schema") {
		t.Fatalf("expected unsupported schema, got %v", err)
	}
}
