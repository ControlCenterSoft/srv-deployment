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

type packageEntry struct {
	name string
	mode int64
	data []byte
}

func main() {
	if len(os.Args) < 2 {
		usage()
	}
	switch os.Args[1] {
	case "package":
		runPackageV1(os.Args[2:])
	case "package-v2":
		runPackageV2(os.Args[2:])
	default:
		usage()
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: release-tool package --binary PATH --version VERSION --commit SHA --arch amd64|arm64 --private-key PATH --output PATH")
	fmt.Fprintln(os.Stderr, "       release-tool package-v2 --binary PATH --worker PATH --version VERSION --commit SHA --arch amd64|arm64 --private-key PATH --output PATH")
	os.Exit(2)
}

func runPackageV1(args []string) {
	fs := flag.NewFlagSet("package", flag.ExitOnError)
	binary := fs.String("binary", "", "release binary")
	version := fs.String("version", "", "semantic version")
	channel := fs.String("channel", "beta", "beta or stable")
	commit := fs.String("commit", "", "source commit SHA")
	arch := fs.String("arch", "", "amd64 or arm64")
	privateKey := fs.String("private-key", "", "Ed25519 private key PEM")
	output := fs.String("output", "", "output tar.gz")
	builtAt := fs.String("built-at", time.Now().UTC().Format(time.RFC3339), "build timestamp")
	_ = fs.Parse(args)
	if *binary == "" || *version == "" || *commit == "" || *arch == "" || *privateKey == "" || *output == "" {
		fs.Usage()
		os.Exit(2)
	}
	artifact, metadata, err := readArtifact("control-center", *binary)
	must(err)
	m := release.Manifest{
		Schema: release.ManifestSchema, Product: "Control Center", Version: *version, Channel: *channel,
		Commit: *commit, BuiltAt: *builtAt, OS: "linux", Arch: *arch, StateSchemaMin: 1, StateSchemaMax: 1,
		Artifact: metadata,
	}
	must(m.Validate())
	manifest := marshalManifest(m)
	priv := loadPrivateKey(*privateKey)
	sig := ed25519.Sign(priv, manifest)
	modTime := parseBuiltAt(*builtAt)
	must(writePackage(*output, []packageEntry{
		{name: "manifest.json", mode: 0o444, data: manifest},
		{name: "manifest.sig", mode: 0o444, data: sig},
		{name: "control-center", mode: 0o555, data: artifact},
	}, modTime))
	fmt.Println(*output)
}

func runPackageV2(args []string) {
	fs := flag.NewFlagSet("package-v2", flag.ExitOnError)
	binary := fs.String("binary", "", "control-center release binary")
	worker := fs.String("worker", "", "control-center-privileged-worker release binary")
	version := fs.String("version", "", "semantic version")
	channel := fs.String("channel", "beta", "beta or stable")
	commit := fs.String("commit", "", "source commit SHA")
	arch := fs.String("arch", "", "amd64 or arm64")
	privateKey := fs.String("private-key", "", "Ed25519 private key PEM")
	output := fs.String("output", "", "output tar.gz")
	builtAt := fs.String("built-at", time.Now().UTC().Format(time.RFC3339), "build timestamp")
	_ = fs.Parse(args)
	if *binary == "" || *worker == "" || *version == "" || *commit == "" || *arch == "" || *privateKey == "" || *output == "" {
		fs.Usage()
		os.Exit(2)
	}

	primaryBytes, primaryMeta, err := readArtifact("control-center", *binary)
	must(err)
	workerBytes, workerMeta, err := readArtifact("control-center-privileged-worker", *worker)
	must(err)

	// The schema-1 bootstrap manifest authenticates the candidate main runtime
	// with the already accepted 1.0.0 verifier. Only after that trust bridge is
	// established may the candidate verifier authenticate the schema-2 pair.
	bootstrap := release.Manifest{
		Schema: release.ManifestSchema, Product: "Control Center", Version: *version, Channel: *channel,
		Commit: *commit, BuiltAt: *builtAt, OS: "linux", Arch: *arch, StateSchemaMin: 1, StateSchemaMax: 1,
		Artifact: primaryMeta,
	}
	must(bootstrap.Validate())
	bootstrapManifest := marshalManifest(bootstrap)

	m := release.ManifestV2{
		Schema: release.ManifestSchemaV2, Product: "Control Center", Version: *version, Channel: *channel,
		Commit: *commit, BuiltAt: *builtAt, OS: "linux", Arch: *arch, StateSchemaMin: 1, StateSchemaMax: 1,
		Artifacts: []release.Artifact{primaryMeta, workerMeta},
	}
	must(m.Validate())
	manifest := marshalManifest(m)

	priv := loadPrivateKey(*privateKey)
	bootstrapSig := ed25519.Sign(priv, bootstrapManifest)
	sig := ed25519.Sign(priv, manifest)
	modTime := parseBuiltAt(*builtAt)
	must(writePackage(*output, []packageEntry{
		{name: "bootstrap-manifest.json", mode: 0o444, data: bootstrapManifest},
		{name: "bootstrap-manifest.sig", mode: 0o444, data: bootstrapSig},
		{name: "manifest.json", mode: 0o444, data: manifest},
		{name: "manifest.sig", mode: 0o444, data: sig},
		{name: "control-center", mode: 0o555, data: primaryBytes},
		{name: "control-center-privileged-worker", mode: 0o555, data: workerBytes},
	}, modTime))
	fmt.Println(*output)
}

func readArtifact(name, path string) ([]byte, release.Artifact, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, release.Artifact{}, err
	}
	if len(data) == 0 {
		return nil, release.Artifact{}, fmt.Errorf("artifact %s is empty", name)
	}
	sum := sha256.Sum256(data)
	return data, release.Artifact{Name: name, SHA256: hex.EncodeToString(sum[:]), Size: int64(len(data))}, nil
}

func marshalManifest(v any) []byte {
	manifest, err := json.MarshalIndent(v, "", "  ")
	must(err)
	return append(manifest, '\n')
}

func loadPrivateKey(path string) ed25519.PrivateKey {
	keyPEM, err := os.ReadFile(path)
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
	return priv
}

func parseBuiltAt(value string) time.Time {
	t, err := time.Parse(time.RFC3339, value)
	must(err)
	return t.UTC()
}

func writePackage(path string, entries []packageEntry, modTime time.Time) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	gz := gzip.NewWriter(f)
	gz.Header.ModTime = time.Unix(0, 0).UTC()
	gz.Header.OS = 255
	tw := tar.NewWriter(gz)
	for _, e := range entries {
		if err := tw.WriteHeader(&tar.Header{Name: e.name, Mode: e.mode, Size: int64(len(e.data)), ModTime: modTime}); err != nil {
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
