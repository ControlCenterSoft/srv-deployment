package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/ControlCenterSoft/srv-deployment/internal/release"
	"github.com/ControlCenterSoft/srv-deployment/internal/state"
)

func TestVerifyReleaseV2CLI(t *testing.T) {
	fixture := newVerifyV2CLIFixture(t)

	for _, field := range []struct {
		name string
		want string
	}{
		{name: "release-id", want: fixture.releaseID},
		{name: "version", want: "1.1.0"},
		{name: "commit", want: fixture.commit},
	} {
		t.Run(field.name, func(t *testing.T) {
			stdout, stderr, code := runVerifyV2Helper(t,
				"--manifest", fixture.manifest,
				"--signature", fixture.signature,
				"--public-key", fixture.publicKey,
				"--artifact", fixture.artifact,
				"--worker", fixture.worker,
				"--field", field.name,
			)
			if code != 0 {
				t.Fatalf("verify-release-v2 exited %d: %s", code, stderr)
			}
			if strings.TrimSpace(stdout) != field.want {
				t.Fatalf("unexpected %s output: got %q want %q", field.name, strings.TrimSpace(stdout), field.want)
			}
		})
	}
}

func TestVerifyReleaseV2CLIMissingWorkerIsUsageError(t *testing.T) {
	fixture := newVerifyV2CLIFixture(t)
	_, _, code := runVerifyV2Helper(t,
		"--manifest", fixture.manifest,
		"--signature", fixture.signature,
		"--public-key", fixture.publicKey,
		"--artifact", fixture.artifact,
	)
	if code != 2 {
		t.Fatalf("missing --worker exit code: got %d want 2", code)
	}
}

func TestVerifyReleaseV2CLITamperedWorkerFailsClosed(t *testing.T) {
	fixture := newVerifyV2CLIFixture(t)
	workerBytes, err := os.ReadFile(fixture.worker)
	if err != nil {
		t.Fatal(err)
	}
	workerBytes[0] ^= 0xff
	if err := os.WriteFile(fixture.worker, workerBytes, 0o600); err != nil {
		t.Fatal(err)
	}

	_, stderr, code := runVerifyV2Helper(t,
		"--manifest", fixture.manifest,
		"--signature", fixture.signature,
		"--public-key", fixture.publicKey,
		"--artifact", fixture.artifact,
		"--worker", fixture.worker,
	)
	if code != 1 {
		t.Fatalf("tampered worker exit code: got %d want 1; stderr=%s", code, stderr)
	}
	if !strings.Contains(stderr, "SHA-256 mismatch") {
		t.Fatalf("tampered worker must report digest failure, got: %s", stderr)
	}
}

func TestVerifyReleaseV2CLIHelper(t *testing.T) {
	if os.Getenv("CONTROL_CENTER_VERIFY_V2_HELPER") != "1" {
		return
	}
	sep := -1
	for i, arg := range os.Args {
		if arg == "--" {
			sep = i
			break
		}
	}
	if sep < 0 || sep+1 >= len(os.Args) {
		os.Exit(97)
	}
	verifyReleaseV2(os.Args[sep+1:])
	os.Exit(0)
}

type verifyV2CLIFixture struct {
	manifest  string
	signature string
	publicKey string
	artifact  string
	worker    string
	releaseID string
	commit    string
}

func newVerifyV2CLIFixture(t *testing.T) verifyV2CLIFixture {
	t.Helper()
	dir := t.TempDir()
	mainBytes := []byte("control-center-cli-fixture")
	workerBytes := []byte("privileged-worker-cli-fixture")
	mainSum := sha256.Sum256(mainBytes)
	workerSum := sha256.Sum256(workerBytes)
	commit := "0123456789abcdef0123456789abcdef01234567"
	m := release.ManifestV2{
		Schema:         release.ManifestSchemaV2,
		Product:        "Control Center",
		Version:        "1.1.0",
		Channel:        "beta",
		Commit:         commit,
		BuiltAt:        "2026-08-21T00:00:00Z",
		OS:             runtime.GOOS,
		Arch:           runtime.GOARCH,
		StateSchemaMin: state.SchemaVersion,
		StateSchemaMax: state.SchemaVersion,
		Artifacts: []release.Artifact{
			{Name: "control-center", SHA256: hex.EncodeToString(mainSum[:]), Size: int64(len(mainBytes))},
			{Name: "control-center-privileged-worker", SHA256: hex.EncodeToString(workerSum[:]), Size: int64(len(workerBytes))},
		},
	}
	manifestBytes, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	manifestBytes = append(manifestBytes, '\n')

	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	pubDER, err := x509.MarshalPKIXPublicKey(pub)
	if err != nil {
		t.Fatal(err)
	}
	pubPEM := pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: pubDER})

	f := verifyV2CLIFixture{
		manifest:  filepath.Join(dir, "manifest.json"),
		signature: filepath.Join(dir, "manifest.sig"),
		publicKey: filepath.Join(dir, "public.pem"),
		artifact:  filepath.Join(dir, "control-center"),
		worker:    filepath.Join(dir, "control-center-privileged-worker"),
		commit:    commit,
	}
	mustWriteCLIFile(t, f.manifest, manifestBytes)
	mustWriteCLIFile(t, f.signature, ed25519.Sign(priv, manifestBytes))
	mustWriteCLIFile(t, f.publicKey, pubPEM)
	mustWriteCLIFile(t, f.artifact, mainBytes)
	mustWriteCLIFile(t, f.worker, workerBytes)

	verified, err := release.VerifyV2(
		f.manifest,
		f.signature,
		f.publicKey,
		map[string]string{
			"control-center":                   f.artifact,
			"control-center-privileged-worker": f.worker,
		},
		runtime.GOOS,
		runtime.GOARCH,
		state.SchemaVersion,
	)
	if err != nil {
		t.Fatal(err)
	}
	f.releaseID = verified.ReleaseID()
	return f
}

func runVerifyV2Helper(t *testing.T, args ...string) (string, string, int) {
	t.Helper()
	cmdArgs := []string{"-test.run=^TestVerifyReleaseV2CLIHelper$", "--"}
	cmdArgs = append(cmdArgs, args...)
	cmd := exec.Command(os.Args[0], cmdArgs...)
	cmd.Env = append(os.Environ(), "CONTROL_CENTER_VERIFY_V2_HELPER=1")
	var stdout, stderr strings.Builder
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	if err == nil {
		return stdout.String(), stderr.String(), 0
	}
	var exitErr *exec.ExitError
	if !errors.As(err, &exitErr) {
		t.Fatalf("helper execution failed: %v", err)
	}
	return stdout.String(), stderr.String(), exitErr.ExitCode()
}

func mustWriteCLIFile(t *testing.T, path string, data []byte) {
	t.Helper()
	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatal(err)
	}
}
