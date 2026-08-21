package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"crypto/ed25519"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"

	"github.com/ControlCenterSoft/srv-deployment/internal/release"
)

func TestReadArtifactMetadata(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "worker")
	want := []byte("worker-bytes")
	if err := os.WriteFile(path, want, 0o600); err != nil {
		t.Fatal(err)
	}
	got, meta, err := readArtifact("control-center-privileged-worker", path)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, want) {
		t.Fatalf("artifact bytes mismatch: got %q want %q", got, want)
	}
	if meta.Name != "control-center-privileged-worker" || meta.Size != int64(len(want)) {
		t.Fatalf("unexpected metadata: %+v", meta)
	}
	if len(meta.SHA256) != 64 {
		t.Fatalf("unexpected SHA-256 length: %d", len(meta.SHA256))
	}
}

func TestReadArtifactRejectsEmpty(t *testing.T) {
	path := filepath.Join(t.TempDir(), "empty")
	if err := os.WriteFile(path, nil, 0o600); err != nil {
		t.Fatal(err)
	}
	if _, _, err := readArtifact("control-center", path); err == nil {
		t.Fatal("expected empty artifact to be rejected")
	}
}

func TestWritePackageDeterministicAndOrdered(t *testing.T) {
	modTime := time.Date(2026, 8, 21, 3, 55, 0, 0, time.UTC)
	entries := []packageEntry{
		{name: "manifest.json", mode: 0o444, data: []byte("{}\n")},
		{name: "manifest.sig", mode: 0o444, data: bytes.Repeat([]byte{0x42}, 64)},
		{name: "control-center", mode: 0o555, data: []byte("api")},
		{name: "control-center-privileged-worker", mode: 0o555, data: []byte("worker")},
	}
	dir := t.TempDir()
	first := filepath.Join(dir, "first.tar.gz")
	second := filepath.Join(dir, "second.tar.gz")
	if err := writePackage(first, entries, modTime); err != nil {
		t.Fatal(err)
	}
	if err := writePackage(second, entries, modTime); err != nil {
		t.Fatal(err)
	}
	firstBytes, err := os.ReadFile(first)
	if err != nil {
		t.Fatal(err)
	}
	secondBytes, err := os.ReadFile(second)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(firstBytes, secondBytes) {
		t.Fatal("release package is not byte-for-byte reproducible")
	}

	names, modes, payloads := readTarGz(t, first, modTime)
	wantNames := []string{"manifest.json", "manifest.sig", "control-center", "control-center-privileged-worker"}
	wantModes := []int64{0o444, 0o444, 0o555, 0o555}
	if !reflect.DeepEqual(names, wantNames) {
		t.Fatalf("entries=%v want=%v", names, wantNames)
	}
	if !reflect.DeepEqual(modes, wantModes) {
		t.Fatalf("modes=%v want=%v", modes, wantModes)
	}
	for i := range entries {
		if !bytes.Equal(payloads[i], entries[i].data) {
			t.Fatalf("payload mismatch for %s", entries[i].name)
		}
	}
}

func TestPackageV2CarriesSchema1TrustBridgeAndSchema2Pair(t *testing.T) {
	dir := t.TempDir()
	binary := filepath.Join(dir, "control-center")
	worker := filepath.Join(dir, "worker")
	keyPath := filepath.Join(dir, "private.pem")
	output := filepath.Join(dir, "release.tar.gz")
	if err := os.WriteFile(binary, []byte("authenticated-main-runtime"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(worker, []byte("authenticated-worker-runtime"), 0o700); err != nil {
		t.Fatal(err)
	}
	_, priv, err := ed25519.GenerateKey(nil)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKCS8PrivateKey(priv)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(keyPath, pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der}), 0o600); err != nil {
		t.Fatal(err)
	}
	builtAt := "2026-08-21T04:00:00Z"
	commit := "0123456789abcdef0123456789abcdef01234567"
	runPackageV2([]string{
		"--binary", binary,
		"--worker", worker,
		"--version", "1.1.0-rc.1",
		"--channel", "beta",
		"--commit", commit,
		"--arch", "amd64",
		"--private-key", keyPath,
		"--output", output,
		"--built-at", builtAt,
	})

	names, modes, payloads := readTarGz(t, output, parseBuiltAt(builtAt))
	wantNames := []string{
		"bootstrap-manifest.json", "bootstrap-manifest.sig",
		"manifest.json", "manifest.sig",
		"control-center", "control-center-privileged-worker",
	}
	wantModes := []int64{0o444, 0o444, 0o444, 0o444, 0o555, 0o555}
	if !reflect.DeepEqual(names, wantNames) {
		t.Fatalf("entries=%v want=%v", names, wantNames)
	}
	if !reflect.DeepEqual(modes, wantModes) {
		t.Fatalf("modes=%v want=%v", modes, wantModes)
	}
	if len(payloads[1]) != ed25519.SignatureSize || len(payloads[3]) != ed25519.SignatureSize {
		t.Fatal("both manifests must carry Ed25519 signatures")
	}
	var bootstrap release.Manifest
	if err := json.Unmarshal(payloads[0], &bootstrap); err != nil {
		t.Fatal(err)
	}
	var v2 release.ManifestV2
	if err := json.Unmarshal(payloads[2], &v2); err != nil {
		t.Fatal(err)
	}
	if bootstrap.Schema != release.ManifestSchema || bootstrap.Artifact.Name != "control-center" {
		t.Fatalf("unexpected bootstrap manifest: %+v", bootstrap)
	}
	if v2.Schema != release.ManifestSchemaV2 || len(v2.Artifacts) != 2 {
		t.Fatalf("unexpected v2 manifest: %+v", v2)
	}
	if bootstrap.Version != v2.Version || bootstrap.Commit != v2.Commit {
		t.Fatal("schema-1 bootstrap and schema-2 manifest identities diverge")
	}
	if !bytes.Equal(payloads[4], []byte("authenticated-main-runtime")) || !bytes.Equal(payloads[5], []byte("authenticated-worker-runtime")) {
		t.Fatal("runtime payloads changed while packaging")
	}
}

func readTarGz(t *testing.T, path string, modTime time.Time) ([]string, []int64, [][]byte) {
	t.Helper()
	f, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	gz, err := gzip.NewReader(f)
	if err != nil {
		t.Fatal(err)
	}
	defer gz.Close()
	tr := tar.NewReader(gz)
	var names []string
	var modes []int64
	var payloads [][]byte
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatal(err)
		}
		data, err := io.ReadAll(tr)
		if err != nil {
			t.Fatal(err)
		}
		names = append(names, hdr.Name)
		modes = append(modes, hdr.Mode)
		payloads = append(payloads, data)
		if !hdr.ModTime.Equal(modTime) {
			t.Fatalf("entry %s modtime=%s want=%s", hdr.Name, hdr.ModTime, modTime)
		}
	}
	return names, modes, payloads
}
