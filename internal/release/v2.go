package release

import (
	"bytes"
	"crypto/ed25519"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"os"
	"runtime"
	"time"
)

// ManifestSchemaV2 расширяет подписанный release contract несколькими
// обязательными runtime-артефактами, не изменяя legacy schema 1.
const ManifestSchemaV2 = 2

// ManifestV2 описывает атомарную пару runtime + privileged worker.
// Schema 1 остаётся неизменной для frozen 1.0.0 и старого updater.
type ManifestV2 struct {
	Schema         int        `json:"schema"`
	Product        string     `json:"product"`
	Version        string     `json:"version"`
	Channel        string     `json:"channel"`
	Commit         string     `json:"commit"`
	BuiltAt        string     `json:"built_at"`
	OS             string     `json:"os"`
	Arch           string     `json:"arch"`
	StateSchemaMin int        `json:"state_schema_min"`
	StateSchemaMax int        `json:"state_schema_max"`
	Artifacts      []Artifact `json:"artifacts"`
}

func DecodeV2(data []byte) (ManifestV2, error) {
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	var m ManifestV2
	if err := dec.Decode(&m); err != nil {
		return ManifestV2{}, fmt.Errorf("decode manifest v2: %w", err)
	}
	var extra any
	if err := dec.Decode(&extra); !errors.Is(err, io.EOF) {
		if err == nil {
			return ManifestV2{}, errors.New("manifest v2 contains multiple JSON values")
		}
		return ManifestV2{}, fmt.Errorf("manifest v2 contains invalid trailing data: %w", err)
	}
	if err := m.Validate(); err != nil {
		return ManifestV2{}, err
	}
	return m, nil
}

func (m ManifestV2) Validate() error {
	if m.Schema != ManifestSchemaV2 {
		return fmt.Errorf("unsupported manifest v2 schema: %d", m.Schema)
	}
	if m.Product != "Control Center" {
		return errors.New("manifest v2 product mismatch")
	}
	if _, err := parseSemVer(m.Version); err != nil {
		return errors.New("invalid release version")
	}
	if _, err := time.Parse(time.RFC3339, m.BuiltAt); err != nil {
		return errors.New("invalid release built_at")
	}
	if m.Channel != "beta" && m.Channel != "stable" {
		return errors.New("invalid release channel")
	}
	if !commitRE.MatchString(m.Commit) {
		return errors.New("invalid release commit")
	}
	if m.OS != "linux" {
		return errors.New("unsupported release OS")
	}
	if m.Arch != "amd64" && m.Arch != "arm64" {
		return errors.New("unsupported release architecture")
	}
	if m.StateSchemaMin < 1 || m.StateSchemaMax < m.StateSchemaMin {
		return errors.New("invalid state schema compatibility range")
	}
	if len(m.Artifacts) != 2 {
		return errors.New("manifest v2 must contain exactly two runtime artifacts")
	}
	seen := map[string]bool{}
	for _, artifact := range m.Artifacts {
		if seen[artifact.Name] {
			return errors.New("manifest v2 contains duplicate artifact names")
		}
		seen[artifact.Name] = true
		if !digestRE.MatchString(artifact.SHA256) || artifact.Size <= 0 {
			return fmt.Errorf("invalid release artifact metadata: %s", artifact.Name)
		}
	}
	if !seen["control-center"] || !seen["control-center-privileged-worker"] {
		return errors.New("manifest v2 requires control-center and control-center-privileged-worker artifacts")
	}
	return nil
}

func (m ManifestV2) Artifact(name string) (Artifact, bool) {
	for _, artifact := range m.Artifacts {
		if artifact.Name == name {
			return artifact, true
		}
	}
	return Artifact{}, false
}

func (m ManifestV2) ReleaseID() string {
	primary, ok := m.Artifact("control-center")
	if !ok {
		return ""
	}
	return fmt.Sprintf("%s-%s-%s", m.Version, m.Commit[:12], primary.SHA256[:12])
}

// VerifyV2 проверяет Ed25519-подпись manifest и оба runtime-артефакта.
// Проверка завершается до любого privileged/systemd изменения.
func VerifyV2(manifestPath, signaturePath, publicKeyPath string, artifactPaths map[string]string, expectedOS, expectedArch string, currentStateSchema int) (ManifestV2, error) {
	manifestBytes, err := os.ReadFile(manifestPath)
	if err != nil {
		return ManifestV2{}, fmt.Errorf("read manifest v2: %w", err)
	}
	sig, err := os.ReadFile(signaturePath)
	if err != nil {
		return ManifestV2{}, fmt.Errorf("read signature: %w", err)
	}
	pubPEM, err := os.ReadFile(publicKeyPath)
	if err != nil {
		return ManifestV2{}, fmt.Errorf("read public key: %w", err)
	}
	block, rest := pem.Decode(pubPEM)
	if block == nil || len(bytes.TrimSpace(rest)) != 0 {
		return ManifestV2{}, errors.New("invalid public key PEM")
	}
	parsed, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return ManifestV2{}, fmt.Errorf("parse public key: %w", err)
	}
	pub, ok := parsed.(ed25519.PublicKey)
	if !ok {
		return ManifestV2{}, errors.New("update public key is not Ed25519")
	}
	if len(sig) != ed25519.SignatureSize || !ed25519.Verify(pub, manifestBytes, sig) {
		return ManifestV2{}, errors.New("release manifest v2 signature verification failed")
	}
	m, err := DecodeV2(manifestBytes)
	if err != nil {
		return ManifestV2{}, err
	}
	if expectedOS == "" {
		expectedOS = runtime.GOOS
	}
	if expectedArch == "" {
		expectedArch = runtime.GOARCH
	}
	if m.OS != expectedOS || m.Arch != expectedArch {
		return ManifestV2{}, fmt.Errorf("release platform mismatch: got %s/%s want %s/%s", m.OS, m.Arch, expectedOS, expectedArch)
	}
	if currentStateSchema < m.StateSchemaMin || currentStateSchema > m.StateSchemaMax {
		return ManifestV2{}, fmt.Errorf("state schema %d is outside compatible range %d..%d", currentStateSchema, m.StateSchemaMin, m.StateSchemaMax)
	}
	for _, artifact := range m.Artifacts {
		path := artifactPaths[artifact.Name]
		if path == "" {
			return ManifestV2{}, fmt.Errorf("artifact path is required: %s", artifact.Name)
		}
		if err := verifyV2Artifact(path, artifact); err != nil {
			return ManifestV2{}, err
		}
	}
	return m, nil
}

func verifyV2Artifact(path string, artifact Artifact) error {
	f, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("open artifact %s: %w", artifact.Name, err)
	}
	h := sha256.New()
	n, err := io.Copy(h, f)
	_ = f.Close()
	if err != nil {
		return fmt.Errorf("hash artifact %s: %w", artifact.Name, err)
	}
	if n != artifact.Size {
		return fmt.Errorf("artifact %s size mismatch: got %d want %d", artifact.Name, n, artifact.Size)
	}
	got := hex.EncodeToString(h.Sum(nil))
	if got != artifact.SHA256 {
		return fmt.Errorf("artifact %s SHA-256 mismatch", artifact.Name)
	}
	return nil
}
