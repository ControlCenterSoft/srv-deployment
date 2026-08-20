package release

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"os"
	"path/filepath"
	"testing"
)

func TestVerifySignedManifestAndTamperFailure(t *testing.T) {
	dir := t.TempDir()
	artifact := []byte("signed candidate")
	artifactPath := filepath.Join(dir, "control-center")
	if err := os.WriteFile(artifactPath, artifact, 0o755); err != nil {
		t.Fatal(err)
	}
	sum := sha256Bytes(artifact)
	m := Manifest{Schema: 1, Product: "Control Center", Version: "1.0.0-beta.1", Channel: "beta", Commit: "0123456789abcdef0123456789abcdef01234567", BuiltAt: "2026-08-20T00:00:00Z", OS: "linux", Arch: "amd64", StateSchemaMin: 1, StateSchemaMax: 1, Artifact: Artifact{Name: "control-center", SHA256: sum, Size: int64(len(artifact))}}
	manifestBytes, _ := json.MarshalIndent(m, "", "  ")
	manifestBytes = append(manifestBytes, '\n')
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	pubDER, _ := x509.MarshalPKIXPublicKey(pub)
	pubPath := filepath.Join(dir, "public.pem")
	if err := os.WriteFile(pubPath, pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: pubDER}), 0o644); err != nil {
		t.Fatal(err)
	}
	manifestPath := filepath.Join(dir, "manifest.json")
	sigPath := filepath.Join(dir, "manifest.sig")
	if err := os.WriteFile(manifestPath, manifestBytes, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(sigPath, ed25519.Sign(priv, manifestBytes), 0o644); err != nil {
		t.Fatal(err)
	}
	got, err := Verify(manifestPath, sigPath, pubPath, artifactPath, "linux", "amd64", 1)
	if err != nil || got.Version != m.Version {
		t.Fatalf("verify err=%v got=%+v", err, got)
	}
	manifestBytes[10] ^= 1
	if err := os.WriteFile(manifestPath, manifestBytes, 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := Verify(manifestPath, sigPath, pubPath, artifactPath, "linux", "amd64", 1); err == nil {
		t.Fatal("tampered manifest verified")
	}
}

func TestCompareVersions(t *testing.T) {
	cases := []struct {
		a, b string
		want int
	}{
		{"1.0.0-beta.1", "1.0.0-beta.2", -1},
		{"1.0.0-beta.2", "1.0.0", -1},
		{"1.0.0", "1.0.0", 0},
		{"1.1.0", "1.0.9", 1},
		{"1.0.0-beta.2+build1", "1.0.0-beta.2+build2", 0},
		{"999999999999999999999999999999.0.0", "2.0.0", 1},
		{"1.0.0-beta.999999999999999999999999999999", "1.0.0-beta.2", 1},
	}
	for _, tc := range cases {
		got, err := CompareVersions(tc.a, tc.b)
		if err != nil {
			t.Fatal(err)
		}
		if got != tc.want {
			t.Fatalf("compare %s %s = %d want %d", tc.a, tc.b, got, tc.want)
		}
	}
}

func sha256Bytes(b []byte) string {
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:])
}

func TestDecodeRejectsInvalidTrailingDataAndBuiltAt(t *testing.T) {
	base := Manifest{
		Schema: 1, Product: "Control Center", Version: "1.0.0-beta.1", Channel: "beta",
		Commit: "0123456789abcdef0123456789abcdef01234567", BuiltAt: "2026-08-20T00:00:00Z",
		OS: "linux", Arch: "amd64", StateSchemaMin: 1, StateSchemaMax: 1,
		Artifact: Artifact{Name: "control-center", SHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", Size: 1},
	}
	data, err := json.Marshal(base)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := Decode(append(append([]byte{}, data...), []byte(" trailing")...)); err == nil {
		t.Fatal("manifest with trailing garbage was accepted")
	}
	base.BuiltAt = "not-a-time"
	data, _ = json.Marshal(base)
	if _, err := Decode(data); err == nil {
		t.Fatal("manifest with invalid built_at was accepted")
	}
}

func TestStrictSemVerValidation(t *testing.T) {
	valid := []string{
		"0.0.0",
		"1.0.0-beta.1",
		"1.0.0-alpha-1.0+build.007",
		"10.20.30+metadata",
	}
	for _, version := range valid {
		if _, err := parseSemVer(version); err != nil {
			t.Fatalf("valid version %q rejected: %v", version, err)
		}
	}
	invalid := []string{
		"01.0.0",
		"1.01.0",
		"1.0.01",
		"1.0.0-beta..1",
		"1.0.0-01",
		"1.0.0+build..1",
		"1.0.0-",
	}
	for _, version := range invalid {
		if _, err := parseSemVer(version); err == nil {
			t.Fatalf("invalid version %q accepted", version)
		}
	}
}

func TestVerifyRejectsArtifactPlatformAndSchemaMismatch(t *testing.T) {
	dir := t.TempDir()
	artifact := []byte("signed candidate")
	artifactPath := filepath.Join(dir, "control-center")
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	pubDER, err := x509.MarshalPKIXPublicKey(pub)
	if err != nil {
		t.Fatal(err)
	}
	pubPath := filepath.Join(dir, "public.pem")
	if err := os.WriteFile(pubPath, pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: pubDER}), 0o644); err != nil {
		t.Fatal(err)
	}
	manifestPath := filepath.Join(dir, "manifest.json")
	sigPath := filepath.Join(dir, "manifest.sig")

	writeFixture := func(m Manifest, body []byte) {
		t.Helper()
		if err := os.WriteFile(artifactPath, body, 0o755); err != nil {
			t.Fatal(err)
		}
		manifestBytes, err := json.MarshalIndent(m, "", "  ")
		if err != nil {
			t.Fatal(err)
		}
		manifestBytes = append(manifestBytes, '\n')
		if err := os.WriteFile(manifestPath, manifestBytes, 0o644); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(sigPath, ed25519.Sign(priv, manifestBytes), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	base := Manifest{
		Schema: 1, Product: "Control Center", Version: "1.0.0-beta.1", Channel: "beta",
		Commit: "0123456789abcdef0123456789abcdef01234567", BuiltAt: "2026-08-20T00:00:00Z",
		OS: "linux", Arch: "amd64", StateSchemaMin: 1, StateSchemaMax: 1,
		Artifact: Artifact{Name: "control-center", SHA256: sha256Bytes(artifact), Size: int64(len(artifact))},
	}
	writeFixture(base, artifact)
	if _, err := Verify(manifestPath, sigPath, pubPath, artifactPath, "linux", "amd64", 1); err != nil {
		t.Fatalf("valid fixture rejected: %v", err)
	}

	writeFixture(base, append(append([]byte{}, artifact...), '!'))
	if _, err := Verify(manifestPath, sigPath, pubPath, artifactPath, "linux", "amd64", 1); err == nil {
		t.Fatal("artifact size/digest mismatch was accepted")
	}

	wrongDigest := base
	wrongDigest.Artifact.SHA256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
	writeFixture(wrongDigest, artifact)
	if _, err := Verify(manifestPath, sigPath, pubPath, artifactPath, "linux", "amd64", 1); err == nil {
		t.Fatal("artifact SHA-256 mismatch was accepted")
	}

	wrongArch := base
	wrongArch.Arch = "arm64"
	writeFixture(wrongArch, artifact)
	if _, err := Verify(manifestPath, sigPath, pubPath, artifactPath, "linux", "amd64", 1); err == nil {
		t.Fatal("wrong architecture was accepted")
	}

	wrongSchema := base
	wrongSchema.StateSchemaMin = 2
	wrongSchema.StateSchemaMax = 2
	writeFixture(wrongSchema, artifact)
	if _, err := Verify(manifestPath, sigPath, pubPath, artifactPath, "linux", "amd64", 1); err == nil {
		t.Fatal("incompatible state schema was accepted")
	}
}
