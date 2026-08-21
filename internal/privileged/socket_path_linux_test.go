//go:build linux

package privileged

import (
	"errors"
	"net"
	"os"
	"path/filepath"
	"testing"
)

func TestListenUnixRejectsExistingRegularFileWithoutDeletingIt(t *testing.T) {
	path := filepath.Join(t.TempDir(), "worker.sock")
	if err := os.WriteFile(path, []byte("must survive"), 0600); err != nil {
		t.Fatal(err)
	}

	listener, err := ListenUnix(path, 0600)
	if listener != nil {
		listener.Close()
		t.Fatal("listener unexpectedly created")
	}
	if !errors.Is(err, ErrInvalidRequest) {
		t.Fatalf("error=%v", err)
	}
	payload, readErr := os.ReadFile(path)
	if readErr != nil {
		t.Fatalf("protected file disappeared: %v", readErr)
	}
	if string(payload) != "must survive" {
		t.Fatalf("protected file changed: %q", payload)
	}
}

func TestListenUnixRejectsSymlinkWithoutDeletingTarget(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "target")
	path := filepath.Join(dir, "worker.sock")
	if err := os.WriteFile(target, []byte("target survives"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, path); err != nil {
		t.Fatal(err)
	}

	listener, err := ListenUnix(path, 0600)
	if listener != nil {
		listener.Close()
		t.Fatal("listener unexpectedly created")
	}
	if !errors.Is(err, ErrInvalidRequest) {
		t.Fatalf("error=%v", err)
	}
	if _, err := os.Lstat(path); err != nil {
		t.Fatalf("symlink disappeared: %v", err)
	}
	payload, err := os.ReadFile(target)
	if err != nil || string(payload) != "target survives" {
		t.Fatalf("target changed: payload=%q err=%v", payload, err)
	}
}

func TestListenUnixReplacesOwnedStaleUnixSocket(t *testing.T) {
	path := filepath.Join(t.TempDir(), "worker.sock")
	stale, err := net.ListenUnix("unix", &net.UnixAddr{Name: path, Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	if err := stale.Close(); err != nil {
		t.Fatal(err)
	}

	listener, err := ListenUnix(path, 0600)
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	if info, err := os.Lstat(path); err != nil || info.Mode()&os.ModeSocket == 0 {
		t.Fatalf("replacement socket invalid: info=%v err=%v", info, err)
	}
}
