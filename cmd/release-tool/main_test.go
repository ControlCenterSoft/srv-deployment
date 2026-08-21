package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"
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

	f, err := os.Open(first)
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
