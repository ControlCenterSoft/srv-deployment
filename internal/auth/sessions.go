package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"sync"
	"time"

	"github.com/ControlCenterSoft/srv-deployment/internal/state"
)

type Session struct {
	Username  string
	Role      state.Role
	CSRF      string
	ExpiresAt time.Time
}

type Manager struct {
	mu       sync.Mutex
	sessions map[[32]byte]Session
	ttl      time.Duration
}

func NewManager(ttl time.Duration) *Manager {
	return &Manager{sessions: map[[32]byte]Session{}, ttl: ttl}
}

func randomToken(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

func digest(token string) [32]byte { return sha256.Sum256([]byte(token)) }

func (m *Manager) Create(u state.User) (string, Session, error) {
	token, err := randomToken(32)
	if err != nil {
		return "", Session{}, err
	}
	csrf, err := randomToken(24)
	if err != nil {
		return "", Session{}, err
	}
	s := Session{Username: u.Username, Role: u.Role, CSRF: csrf, ExpiresAt: time.Now().UTC().Add(m.ttl)}
	m.mu.Lock()
	defer m.mu.Unlock()
	m.sessions[digest(token)] = s
	return token, s, nil
}

func (m *Manager) Lookup(token string) (Session, bool) {
	if token == "" {
		return Session{}, false
	}
	key := digest(token)
	m.mu.Lock()
	defer m.mu.Unlock()
	s, ok := m.sessions[key]
	if !ok {
		return Session{}, false
	}
	if time.Now().UTC().After(s.ExpiresAt) {
		delete(m.sessions, key)
		return Session{}, false
	}
	return s, true
}

func (m *Manager) Revoke(token string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.sessions, digest(token))
}

func (m *Manager) RevokeUser(username string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for k, s := range m.sessions {
		if s.Username == username {
			delete(m.sessions, k)
		}
	}
}
