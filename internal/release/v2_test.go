package release

import (
	"bytes"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestManifestV2ValidateRequiresExactRuntimePair(t *testing.T) {
	mainBytes := []byte("main-runtime")
	workerBytes := []byte("worker-runtime")
	m := testManifestV2(mainBytes, workerBytes)
	if err := m.Validate(); err != nil {
		t.Fatalf("valid v2 manifest rejected: %v", err)
	}

	m.Artifacts = m.Artifacts[:1]
	if err := m.Validate(); err == nil {
		t.Fatal("manifest without privileged worker must be rejected")
	}
}

func TestDecodeV2RejectsUnknownFields(t *testing.T) {
	m := testManifestV2([]byte("main"), []byte("worker"))
	data, err := json.Marshal(m)
	if err != nil {
		t.Fatal(err)
	}
	data = bytes.Replace(data, []byte(`"schema":2`), []byte(`"schema":2,"unexpected":true`), 1)
	if bytes.Contains(data, []byte(`"unexpected"`)) {
		t.Fatal("test fixture must use unescaped JSON field names")
	}
	data = bytes.Replace(data, []byte(`"schema":2`), []byte(`"schema":2,"unexpected":true`), 1)
	data = bytes.Replace(data, []byte(`"schema"`), []byte(`"schema"`), 1)
	data = bytes.Replace(data, []byte(`"unexpected"`), []byte(`"unexpected"`), 1)
	data = bytes.Replace(data, []byte(`{"schema":2`), []byte(`{"schema":2,"unexpected":true`), 1)
	if _, err := DecodeV2(data); err == nil {
		t.Fatal("unknown manifest field must be rejected")
	}
}

func TestVerifyV2ChecksSignatureAndBothArtifacts(t *testing.T) {
	dir := t.TempDir()
	mainBytes := []byte("main-runtime-v2")
	workerBytes := []byte("worker-runtime-v2")
	m := testManifestV2(mainBytes, workerBytes)
	manifest, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	manifest = append(manifest, '\n')

	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	pubDER, err := x509.MarshalPKIXPublicKey(pub)
	if err != nil {
		t.Fatal(err)
	}
	pubPEM := pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: pubDER})
	sig := ed25519.Sign(priv, manifest)

	manifestPath := filepath.Join(dir, "manifest.json")
	sigPath := filepath.Join(dir, "manifest.sig")
	keyPath := filepath.Join(dir, "public.pem")
	mainPath := filepath.Join(dir, "control-center")
	workerPath := filepath.Join(dir, "control-center-privileged-worker")
	mustWriteTestFile(t, manifestPath, manifest)
	mustWriteTestFile(t, sigPath, sig)
	mustWriteTestFile(t, keyPath, pubPEM)
	mustWriteTestFile(t, mainPath, mainBytes)
	mustWriteTestFile(t, workerPath, workerBytes)

	paths := map[string]string{
		"control-center":                   mainPath,
		"control-center-privileged-worker": workerPath,
	}
	verified, err := VerifyV2(manifestPath, sigPath, keyPath, paths, "linux", "amd64", 1)
	if err != nil {
		t.Fatalf("valid package rejected: %v", err)
	}
	if verified.ReleaseID() == "" || !strings.HasPrefix(verified.ReleaseID(), "1.1.0-0123456789ab-") {
		t.Fatalf("unexpected release id: %q", verified.ReleaseID())
	}

	mustWriteTestFile(t, workerPath, []byte("tampered-worker"))
	if _, err := VerifyV2(manifestPath, sigPath, keyPath, paths, "linux", "amd64", 1); err == nil || !strings.Contains(err.Error(), "SHA-256 mismatch") {
		t.Fatalf("tampered worker must fail closed, got: %v", err)
	}
}

func testManifestV2(mainBytes, workerBytes []byte) ManifestV2 {
	mainSum := sha256.Sum256(mainBytes)
	workerSum := sha256.Sum256(workerBytes)
	return ManifestV2{
		Schema:         ManifestSchemaV2,
		Product:        "Control Center",
		Version:        "1.1.0",
		Channel:        "beta",
		Commit:         "0123456789abcdef0123456789abcdef01234567",
		BuiltAt:        "2026-08-21T00:00:00Z",
		OS:             "linux",
		Arch:           "amd64",
		StateSchemaMin: 1,
		StateSchemaMax: 1,
		Artifacts: []Artifact{
			{Name: "control-center", SHA256: hex.EncodeToString(mainSum[:]), Size: int64(len(mainBytes))},
			{Name: "control-center-privileged-worker", SHA256: hex.EncodeToString(workerSum[:]), Size: int64(len(workerBytes))},
		},
	}
}

func mustWriteTestFile(t *testing.T, path string, data []byte) {
	t.Helper()
	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatal(err)
	}
}
