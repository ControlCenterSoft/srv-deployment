package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"crypto/ed25519"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"github.com/ControlCenterSoft/srv-deployment/internal/release"
)

func main() {
	if len(os.Args) < 2 || os.Args[1] != "package" {
		fmt.Fprintln(os.Stderr, "usage: release-tool package --binary PATH --version VERSION --commit SHA --arch amd64|arm64 --private-key PATH --output PATH")
		os.Exit(2)
	}
	fs := flag.NewFlagSet("package", flag.ExitOnError)
	binary := fs.String("binary", "", "release binary")
	version := fs.String("version", "", "semantic version")
	channel := fs.String("channel", "beta", "beta or stable")
	commit := fs.String("commit", "", "source commit SHA")
	arch := fs.String("arch", "", "amd64 or arm64")
	privateKey := fs.String("private-key", "", "Ed25519 private key PEM")
	output := fs.String("output", "", "output tar.gz")
	builtAt := fs.String("built-at", time.Now().UTC().Format(time.RFC3339), "build timestamp")
	_ = fs.Parse(os.Args[2:])
	if *binary == "" || *version == "" || *commit == "" || *arch == "" || *privateKey == "" || *output == "" {
		fs.Usage()
		os.Exit(2)
	}
	artifact, err := os.ReadFile(*binary)
	must(err)
	sum := sha256.Sum256(artifact)
	m := release.Manifest{
		Schema: release.ManifestSchema, Product: "Control Center", Version: *version, Channel: *channel,
		Commit: *commit, BuiltAt: *builtAt, OS: "linux", Arch: *arch, StateSchemaMin: 1, StateSchemaMax: 1,
		Artifact: release.Artifact{Name: "control-center", SHA256: hex.EncodeToString(sum[:]), Size: int64(len(artifact))},
	}
	must(m.Validate())
	manifest, err := json.MarshalIndent(m, "", "  ")
	must(err)
	manifest = append(manifest, '\n')
	keyPEM, err := os.ReadFile(*privateKey)
	must(err)
	block, rest := pem.Decode(keyPEM)
	if block == nil || len(bytes.TrimSpace(rest)) != 0 {
		fatal("invalid private key PEM")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	must(err)
	priv, ok := parsed.(ed25519.PrivateKey)
	if !ok {
		fatal("private key is not Ed25519")
	}
	sig := ed25519.Sign(priv, manifest)
	must(writePackage(*output, manifest, sig, artifact))
	fmt.Println(*output)
}

func writePackage(path string, manifest, sig, artifact []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	gz := gzip.NewWriter(f)
	tw := tar.NewWriter(gz)
	now := time.Now().UTC()
	entries := []struct {
		name string
		mode int64
		data []byte
	}{{"manifest.json", 0o444, manifest}, {"manifest.sig", 0o444, sig}, {"control-center", 0o555, artifact}}
	for _, e := range entries {
		if err := tw.WriteHeader(&tar.Header{Name: e.name, Mode: e.mode, Size: int64(len(e.data)), ModTime: now}); err != nil {
			return err
		}
		if _, err := io.Copy(tw, bytes.NewReader(e.data)); err != nil {
			return err
		}
	}
	if err := tw.Close(); err != nil {
		return err
	}
	if err := gz.Close(); err != nil {
		return err
	}
	return f.Sync()
}

func must(err error) {
	if err != nil {
		fatal(err.Error())
	}
}
func fatal(msg string) { fmt.Fprintln(os.Stderr, "release-tool:", msg); os.Exit(1) }
