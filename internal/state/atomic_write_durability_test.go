package state

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestAtomicWritePersistsReplacementAndPinsDirectorySync(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "state.json")
	if err := os.WriteFile(path, []byte("old\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := atomicWrite(path, []byte("new\n"), 0o600); err != nil {
		t.Fatalf("atomicWrite: %v", err)
	}
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != "new\n" {
		t.Fatalf("unexpected replacement content: %q", got)
	}

	// Crash durability of rename metadata cannot be deterministically simulated
	// in a normal unit test. Pin the security-critical ordering so future edits
	// cannot silently drop the parent-directory fsync required by Linux.
	source, err := os.ReadFile("store.go")
	if err != nil {
		t.Fatal(err)
	}
	text := string(source)
	renameAt := strings.Index(text, "if err := os.Rename(name, path); err != nil")
	syncAt := strings.Index(text, "if err := syncDirectory(dir); err != nil")
	if renameAt < 0 || syncAt < 0 || syncAt <= renameAt {
		t.Fatal("atomicWrite must fsync the parent directory after rename")
	}
}
