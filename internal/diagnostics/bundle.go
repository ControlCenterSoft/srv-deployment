package diagnostics

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"encoding/json"
	"fmt"
	"os"
	"runtime"
	"time"

	"github.com/ControlCenterSoft/srv-deployment/internal/buildinfo"
	"github.com/ControlCenterSoft/srv-deployment/internal/observability"
	"github.com/ControlCenterSoft/srv-deployment/internal/operations"
	"github.com/ControlCenterSoft/srv-deployment/internal/state"
)

type publicUser struct {
	Username           string     `json:"username"`
	Role               state.Role `json:"role"`
	Blocked            bool       `json:"blocked"`
	MustChangePassword bool       `json:"must_change_password"`
	CreatedAt          time.Time  `json:"created_at"`
	PasswordChangedAt  time.Time  `json:"password_changed_at"`
}

func Build(startedAt time.Time, operationID string, store *state.Store, audit *observability.AuditLog, ops *operations.Store) ([]byte, error) {
	auditEvents, err := audit.Recent(500)
	if err != nil {
		return nil, fmt.Errorf("read audit: %w", err)
	}
	users := store.ListUsers()
	publicUsers := make([]publicUser, 0, len(users))
	for _, u := range users {
		publicUsers = append(publicUsers, publicUser{Username: u.Username, Role: u.Role, Blocked: u.Blocked, MustChangePassword: u.MustChangePassword, CreatedAt: u.CreatedAt, PasswordChangedAt: u.PasswordChangedAt})
	}
	now := time.Now().UTC()
	files := map[string]any{
		"manifest.json": map[string]any{
			"product":          "Control Center",
			"format":           1,
			"generated_at":     now,
			"operation_id":     operationID,
			"contains_secrets": false,
			"excluded":         []string{"password hashes", "passwords", "bootstrap credentials", "session tokens", "CSRF tokens", "request bodies"},
		},
		"version.json": map[string]any{"version": buildinfo.Version, "commit": buildinfo.Commit, "built_at": buildinfo.BuiltAt, "state_schema": store.Schema()},
		"runtime.json": map[string]any{
			"pid": os.Getpid(), "go_version": runtime.Version(), "goos": runtime.GOOS, "goarch": runtime.GOARCH,
			"goroutines": runtime.NumGoroutine(), "started_at": startedAt.UTC(), "uptime_seconds": now.Sub(startedAt).Seconds(),
		},
		"users.json":      publicUsers,
		"audit.json":      auditEvents,
		"operations.json": ops.List(500),
	}

	var out bytes.Buffer
	gz := gzip.NewWriter(&out)
	tw := tar.NewWriter(gz)
	order := []string{"manifest.json", "version.json", "runtime.json", "users.json", "audit.json", "operations.json"}
	for _, name := range order {
		b, err := json.MarshalIndent(files[name], "", "  ")
		if err != nil {
			_ = tw.Close()
			_ = gz.Close()
			return nil, err
		}
		b = append(b, '\n')
		h := &tar.Header{Name: name, Mode: 0o600, Size: int64(len(b)), ModTime: now}
		if err := tw.WriteHeader(h); err != nil {
			_ = tw.Close()
			_ = gz.Close()
			return nil, err
		}
		if _, err := tw.Write(b); err != nil {
			_ = tw.Close()
			_ = gz.Close()
			return nil, err
		}
	}
	if err := tw.Close(); err != nil {
		_ = gz.Close()
		return nil, err
	}
	if err := gz.Close(); err != nil {
		return nil, err
	}
	return out.Bytes(), nil
}
