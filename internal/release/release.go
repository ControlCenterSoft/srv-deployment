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
	"regexp"
	"runtime"
	"strings"
	"time"
)

const ManifestSchema = 1

var (
	versionRE = regexp.MustCompile(`^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z.-]+))?(?:\+([0-9A-Za-z.-]+))?$`)
	commitRE  = regexp.MustCompile(`^[0-9a-f]{7,64}$`)
	digestRE  = regexp.MustCompile(`^[0-9a-f]{64}$`)
)

type Artifact struct {
	Name   string `json:"name"`
	SHA256 string `json:"sha256"`
	Size   int64  `json:"size"`
}

type Manifest struct {
	Schema         int      `json:"schema"`
	Product        string   `json:"product"`
	Version        string   `json:"version"`
	Channel        string   `json:"channel"`
	Commit         string   `json:"commit"`
	BuiltAt        string   `json:"built_at"`
	OS             string   `json:"os"`
	Arch           string   `json:"arch"`
	StateSchemaMin int      `json:"state_schema_min"`
	StateSchemaMax int      `json:"state_schema_max"`
	Artifact       Artifact `json:"artifact"`
}

func Decode(data []byte) (Manifest, error) {
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	var m Manifest
	if err := dec.Decode(&m); err != nil {
		return Manifest{}, fmt.Errorf("decode manifest: %w", err)
	}
	var extra any
	if err := dec.Decode(&extra); !errors.Is(err, io.EOF) {
		if err == nil {
			return Manifest{}, errors.New("manifest contains multiple JSON values")
		}
		return Manifest{}, fmt.Errorf("manifest contains invalid trailing data: %w", err)
	}
	if err := m.Validate(); err != nil {
		return Manifest{}, err
	}
	return m, nil
}

func (m Manifest) Validate() error {
	if m.Schema != ManifestSchema {
		return fmt.Errorf("unsupported manifest schema: %d", m.Schema)
	}
	if m.Product != "Control Center" {
		return errors.New("manifest product mismatch")
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
	if m.Artifact.Name != "control-center" || !digestRE.MatchString(m.Artifact.SHA256) || m.Artifact.Size <= 0 {
		return errors.New("invalid release artifact metadata")
	}
	return nil
}

func (m Manifest) ReleaseID() string {
	return fmt.Sprintf("%s-%s-%s", m.Version, m.Commit[:12], m.Artifact.SHA256[:12])
}

func Verify(manifestPath, signaturePath, publicKeyPath, artifactPath, expectedOS, expectedArch string, currentStateSchema int) (Manifest, error) {
	manifestBytes, err := os.ReadFile(manifestPath)
	if err != nil {
		return Manifest{}, fmt.Errorf("read manifest: %w", err)
	}
	sig, err := os.ReadFile(signaturePath)
	if err != nil {
		return Manifest{}, fmt.Errorf("read signature: %w", err)
	}
	pubPEM, err := os.ReadFile(publicKeyPath)
	if err != nil {
		return Manifest{}, fmt.Errorf("read public key: %w", err)
	}
	block, rest := pem.Decode(pubPEM)
	if block == nil || len(bytes.TrimSpace(rest)) != 0 {
		return Manifest{}, errors.New("invalid public key PEM")
	}
	parsed, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return Manifest{}, fmt.Errorf("parse public key: %w", err)
	}
	pub, ok := parsed.(ed25519.PublicKey)
	if !ok {
		return Manifest{}, errors.New("update public key is not Ed25519")
	}
	if len(sig) != ed25519.SignatureSize || !ed25519.Verify(pub, manifestBytes, sig) {
		return Manifest{}, errors.New("release manifest signature verification failed")
	}
	m, err := Decode(manifestBytes)
	if err != nil {
		return Manifest{}, err
	}
	if expectedOS == "" {
		expectedOS = runtime.GOOS
	}
	if expectedArch == "" {
		expectedArch = runtime.GOARCH
	}
	if m.OS != expectedOS || m.Arch != expectedArch {
		return Manifest{}, fmt.Errorf("release platform mismatch: got %s/%s want %s/%s", m.OS, m.Arch, expectedOS, expectedArch)
	}
	if currentStateSchema < m.StateSchemaMin || currentStateSchema > m.StateSchemaMax {
		return Manifest{}, fmt.Errorf("state schema %d is outside compatible range %d..%d", currentStateSchema, m.StateSchemaMin, m.StateSchemaMax)
	}
	f, err := os.Open(artifactPath)
	if err != nil {
		return Manifest{}, fmt.Errorf("open artifact: %w", err)
	}
	h := sha256.New()
	n, err := io.Copy(h, f)
	_ = f.Close()
	if err != nil {
		return Manifest{}, fmt.Errorf("hash artifact: %w", err)
	}
	if n != m.Artifact.Size {
		return Manifest{}, fmt.Errorf("artifact size mismatch: got %d want %d", n, m.Artifact.Size)
	}
	got := hex.EncodeToString(h.Sum(nil))
	if got != m.Artifact.SHA256 {
		return Manifest{}, errors.New("artifact SHA-256 mismatch")
	}
	return m, nil
}

type semVersion struct {
	major, minor, patch string
	pre                 []string
}

func parseSemVer(s string) (semVersion, error) {
	matches := versionRE.FindStringSubmatch(s)
	if matches == nil {
		return semVersion{}, fmt.Errorf("invalid semantic version: %s", s)
	}
	major := matches[1]
	minor := matches[2]
	patch := matches[3]
	pre, err := validateIdentifiers(matches[4], true)
	if err != nil {
		return semVersion{}, fmt.Errorf("invalid semantic version: %s", s)
	}
	if _, err := validateIdentifiers(matches[5], false); err != nil {
		return semVersion{}, fmt.Errorf("invalid semantic version: %s", s)
	}
	return semVersion{major: major, minor: minor, patch: patch, pre: pre}, nil
}

func validateIdentifiers(raw string, prerelease bool) ([]string, error) {
	if raw == "" {
		return nil, nil
	}
	parts := strings.Split(raw, ".")
	for _, part := range parts {
		if part == "" {
			return nil, errors.New("empty identifier")
		}
		for _, r := range part {
			if !((r >= '0' && r <= '9') || (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') || r == '-') {
				return nil, errors.New("invalid identifier character")
			}
		}
		if prerelease && len(part) > 1 && part[0] == '0' {
			allDigits := true
			for _, r := range part {
				if r < '0' || r > '9' {
					allDigits = false
					break
				}
			}
			if allDigits {
				return nil, errors.New("numeric prerelease identifier has leading zero")
			}
		}
	}
	return parts, nil
}

func compareNumericIdentifier(a, b string) int {
	if len(a) < len(b) {
		return -1
	}
	if len(a) > len(b) {
		return 1
	}
	if a < b {
		return -1
	}
	if a > b {
		return 1
	}
	return 0
}

func isDigits(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

func CompareVersions(a, b string) (int, error) {
	av, err := parseSemVer(a)
	if err != nil {
		return 0, err
	}
	bv, err := parseSemVer(b)
	if err != nil {
		return 0, err
	}
	for _, pair := range [][2]string{{av.major, bv.major}, {av.minor, bv.minor}, {av.patch, bv.patch}} {
		if cmp := compareNumericIdentifier(pair[0], pair[1]); cmp != 0 {
			return cmp, nil
		}
	}
	if len(av.pre) == 0 && len(bv.pre) == 0 {
		return 0, nil
	}
	if len(av.pre) == 0 {
		return 1, nil
	}
	if len(bv.pre) == 0 {
		return -1, nil
	}
	max := len(av.pre)
	if len(bv.pre) > max {
		max = len(bv.pre)
	}
	for i := 0; i < max; i++ {
		if i >= len(av.pre) {
			return -1, nil
		}
		if i >= len(bv.pre) {
			return 1, nil
		}
		a, b := av.pre[i], bv.pre[i]
		aNumeric, bNumeric := isDigits(a), isDigits(b)
		switch {
		case aNumeric && bNumeric:
			if cmp := compareNumericIdentifier(a, b); cmp != 0 {
				return cmp, nil
			}
		case aNumeric && !bNumeric:
			return -1, nil
		case !aNumeric && bNumeric:
			return 1, nil
		default:
			if a < b {
				return -1, nil
			}
			if a > b {
				return 1, nil
			}
		}
	}
	return 0, nil
}
