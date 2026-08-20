package diagnostics

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"io"
	"strings"
	"testing"
	"time"

	"github.com/ControlCenterSoft/srv-deployment/internal/observability"
	"github.com/ControlCenterSoft/srv-deployment/internal/operations"
	"github.com/ControlCenterSoft/srv-deployment/internal/state"
)

func TestBundleExcludesPasswordMaterial(t *testing.T) {
	root := t.TempDir()
	s, err := state.Open(root + "/state")
	if err != nil {
		t.Fatal(err)
	}
	password, _, err := s.BootstrapAdmin("admin")
	if err != nil {
		t.Fatal(err)
	}
	a, err := observability.OpenAudit(root + "/log")
	if err != nil {
		t.Fatal(err)
	}
	o, err := operations.Open(root + "/state")
	if err != nil {
		t.Fatal(err)
	}
	if err := a.Append(observability.AuditEvent{OperationID: "x", Actor: "admin", Action: "diagnostics.test", Result: "success"}); err != nil {
		t.Fatal(err)
	}
	bundle, err := Build(time.Now().Add(-time.Minute), "export-op", s, a, o)
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(bundle, []byte(password)) {
		t.Fatal("compressed bundle contains plaintext password bytes")
	}
	gz, err := gzip.NewReader(bytes.NewReader(bundle))
	if err != nil {
		t.Fatal(err)
	}
	tr := tar.NewReader(gz)
	seen := map[string]bool{}
	var expanded bytes.Buffer
	for {
		h, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatal(err)
		}
		seen[h.Name] = true
		b, err := io.ReadAll(tr)
		if err != nil {
			t.Fatal(err)
		}
		expanded.Write(b)
	}
	for _, name := range []string{"manifest.json", "version.json", "runtime.json", "users.json", "audit.json", "operations.json"} {
		if !seen[name] {
			t.Fatalf("missing %s", name)
		}
	}
	text := expanded.String()
	if strings.Contains(text, password) || strings.Contains(text, "pbkdf2-sha256") {
		t.Fatal("diagnostic bundle exposes password material")
	}
	if strings.Contains(text, "secrets.json") || strings.Contains(text, "bootstrap-admin.secret") {
		t.Fatal("diagnostic bundle references secret files")
	}
}
