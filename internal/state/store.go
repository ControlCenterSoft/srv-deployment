package state

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"
)

const SchemaVersion = 1

type Role string

const (
	RoleAdmin  Role = "admin"
	RoleViewer Role = "viewer"
)

type User struct {
	Username           string    `json:"username"`
	Role               Role      `json:"role"`
	Blocked            bool      `json:"blocked"`
	MustChangePassword bool      `json:"must_change_password"`
	CreatedAt          time.Time `json:"created_at"`
	PasswordChangedAt  time.Time `json:"password_changed_at"`
}

type document struct {
	Schema   int             `json:"schema"`
	Revision uint64          `json:"revision"`
	Desired  map[string]any  `json:"desired"`
	Observed map[string]any  `json:"observed"`
	Users    map[string]User `json:"users"`
}

type secretDocument struct {
	Schema    int               `json:"schema"`
	Revision  uint64            `json:"revision"`
	Passwords map[string]string `json:"passwords"`
}

type Store struct {
	mu            sync.RWMutex
	dir           string
	statePath     string
	secretPath    string
	bootstrapPath string
	doc           document
	secrets       secretDocument
}

var usernameRE = regexp.MustCompile(`^[a-z][a-z0-9._-]{2,63}$`)

func Open(dir string) (*Store, error) {
	if strings.TrimSpace(dir) == "" {
		return nil, errors.New("state directory is required")
	}
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return nil, fmt.Errorf("create state directory: %w", err)
	}
	s := &Store{
		dir:           dir,
		statePath:     filepath.Join(dir, "state.json"),
		secretPath:    filepath.Join(dir, "secrets.json"),
		bootstrapPath: filepath.Join(dir, "bootstrap-admin.secret"),
		doc:           document{Schema: SchemaVersion, Revision: 1, Desired: map[string]any{}, Observed: map[string]any{}, Users: map[string]User{}},
		secrets:       secretDocument{Schema: SchemaVersion, Revision: 1, Passwords: map[string]string{}},
	}
	if err := s.load(); err != nil {
		return nil, err
	}
	return s, nil
}

func (s *Store) load() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if b, err := os.ReadFile(s.statePath); err == nil {
		if err := json.Unmarshal(b, &s.doc); err != nil {
			return fmt.Errorf("decode state: %w", err)
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("read state: %w", err)
	}
	if b, err := os.ReadFile(s.secretPath); err == nil {
		if err := json.Unmarshal(b, &s.secrets); err != nil {
			return fmt.Errorf("decode secrets: %w", err)
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("read secrets: %w", err)
	}
	if s.doc.Schema != SchemaVersion || s.secrets.Schema != SchemaVersion {
		return fmt.Errorf("unsupported state schema: state=%d secrets=%d", s.doc.Schema, s.secrets.Schema)
	}
	if s.doc.Revision != s.secrets.Revision {
		return fmt.Errorf("state revision mismatch: state=%d secrets=%d; repair required", s.doc.Revision, s.secrets.Revision)
	}
	if s.doc.Users == nil {
		s.doc.Users = map[string]User{}
	}
	if s.doc.Desired == nil {
		s.doc.Desired = map[string]any{}
	}
	if s.doc.Observed == nil {
		s.doc.Observed = map[string]any{}
	}
	if s.secrets.Passwords == nil {
		s.secrets.Passwords = map[string]string{}
	}
	return nil
}

func normalizeUsername(username string) (string, error) {
	username = strings.ToLower(strings.TrimSpace(username))
	if !usernameRE.MatchString(username) {
		return "", errors.New("username must match ^[a-z][a-z0-9._-]{2,63}$")
	}
	return username, nil
}

func (s *Store) BootstrapAdmin(username string) (string, bool, error) {
	username, err := normalizeUsername(username)
	if err != nil {
		return "", false, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.doc.Users) != 0 {
		return "", false, nil
	}
	raw := make([]byte, 24)
	if _, err := rand.Read(raw); err != nil {
		return "", false, err
	}
	password := base64.RawURLEncoding.EncodeToString(raw)
	hash, err := HashPassword(password)
	if err != nil {
		return "", false, err
	}
	now := time.Now().UTC()
	s.doc.Users[username] = User{Username: username, Role: RoleAdmin, MustChangePassword: true, CreatedAt: now, PasswordChangedAt: now}
	s.secrets.Passwords[username] = hash
	s.doc.Revision++
	if err := s.persistLocked(); err != nil {
		return "", false, err
	}
	secret := []byte("username=" + username + "\npassword=" + password + "\n")
	if err := atomicWrite(s.bootstrapPath, secret, 0o600); err != nil {
		return "", false, err
	}
	return password, true, nil
}

func (s *Store) CreateUser(username, password string, role Role) (User, error) {
	username, err := normalizeUsername(username)
	if err != nil {
		return User{}, err
	}
	if role != RoleAdmin && role != RoleViewer {
		return User{}, errors.New("invalid role")
	}
	hash, err := HashPassword(password)
	if err != nil {
		return User{}, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, exists := s.doc.Users[username]; exists {
		return User{}, errors.New("user already exists")
	}
	now := time.Now().UTC()
	user := User{Username: username, Role: role, CreatedAt: now, PasswordChangedAt: now}
	s.doc.Users[username] = user
	s.secrets.Passwords[username] = hash
	s.doc.Revision++
	if err := s.persistLocked(); err != nil {
		return User{}, err
	}
	return user, nil
}

func (s *Store) ListUsers() []User {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]User, 0, len(s.doc.Users))
	for _, u := range s.doc.Users {
		out = append(out, u)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Username < out[j].Username })
	return out
}

func (s *Store) GetUser(username string) (User, bool) {
	username, err := normalizeUsername(username)
	if err != nil {
		return User{}, false
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	u, ok := s.doc.Users[username]
	return u, ok
}

func (s *Store) VerifyCredentials(username, password string) (User, bool) {
	username, err := normalizeUsername(username)
	if err != nil {
		return User{}, false
	}
	s.mu.RLock()
	u, ok := s.doc.Users[username]
	hash := s.secrets.Passwords[username]
	s.mu.RUnlock()
	if !ok || u.Blocked || hash == "" {
		return User{}, false
	}
	if !VerifyPassword(password, hash) {
		return User{}, false
	}
	return u, true
}

func (s *Store) ChangePassword(username, oldPassword, newPassword string) error {
	username, err := normalizeUsername(username)
	if err != nil {
		return err
	}
	newHash, err := HashPassword(newPassword)
	if err != nil {
		return err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	u, ok := s.doc.Users[username]
	if !ok || u.Blocked || !VerifyPassword(oldPassword, s.secrets.Passwords[username]) {
		return errors.New("current password is invalid")
	}
	s.secrets.Passwords[username] = newHash
	u.MustChangePassword = false
	u.PasswordChangedAt = time.Now().UTC()
	s.doc.Users[username] = u
	s.doc.Revision++
	if err := s.persistLocked(); err != nil {
		return err
	}
	_ = os.Remove(s.bootstrapPath)
	return nil
}

func (s *Store) SetBlocked(username string, blocked bool) (User, error) {
	username, err := normalizeUsername(username)
	if err != nil {
		return User{}, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	u, ok := s.doc.Users[username]
	if !ok {
		return User{}, errors.New("user not found")
	}
	if u.Role == RoleAdmin && blocked {
		activeAdmins := 0
		for _, candidate := range s.doc.Users {
			if candidate.Role == RoleAdmin && !candidate.Blocked {
				activeAdmins++
			}
		}
		if activeAdmins <= 1 {
			return User{}, errors.New("cannot block the last active admin")
		}
	}
	u.Blocked = blocked
	s.doc.Users[username] = u
	s.doc.Revision++
	if err := s.persistLocked(); err != nil {
		return User{}, err
	}
	return u, nil
}

func (s *Store) Ready() (bool, string) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	for _, u := range s.doc.Users {
		if u.Role == RoleAdmin && !u.Blocked {
			return true, "ready"
		}
	}
	return false, "no active administrator"
}

func (s *Store) Schema() int { return SchemaVersion }

func (s *Store) persistLocked() error {
	s.secrets.Revision = s.doc.Revision
	stateBytes, err := json.MarshalIndent(s.doc, "", "  ")
	if err != nil {
		return err
	}
	secretBytes, err := json.MarshalIndent(s.secrets, "", "  ")
	if err != nil {
		return err
	}
	if err := atomicWrite(s.secretPath, append(secretBytes, '\n'), 0o600); err != nil {
		return fmt.Errorf("persist secrets: %w", err)
	}
	if err := atomicWrite(s.statePath, append(stateBytes, '\n'), 0o600); err != nil {
		return fmt.Errorf("persist state: %w", err)
	}
	return nil
}

func atomicWrite(path string, data []byte, mode os.FileMode) error {
	dir := filepath.Dir(path)
	f, err := os.CreateTemp(dir, ".tmp-*")
	if err != nil {
		return err
	}
	name := f.Name()
	defer os.Remove(name)
	if err := f.Chmod(mode); err != nil {
		_ = f.Close()
		return err
	}
	if _, err := f.Write(data); err != nil {
		_ = f.Close()
		return err
	}
	if err := f.Sync(); err != nil {
		_ = f.Close()
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	return os.Rename(name, path)
}
