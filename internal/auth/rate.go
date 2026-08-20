package auth

import (
	"sync"
	"time"
)

type rateEntry struct {
	Count int
	Reset time.Time
}

type LoginLimiter struct {
	mu      sync.Mutex
	entries map[string]rateEntry
	limit   int
	window  time.Duration
}

func NewLoginLimiter(limit int, window time.Duration) *LoginLimiter {
	return &LoginLimiter{entries: map[string]rateEntry{}, limit: limit, window: window}
}

func (l *LoginLimiter) Allowed(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := time.Now()
	e := l.entries[key]
	if e.Reset.IsZero() || now.After(e.Reset) {
		delete(l.entries, key)
		return true
	}
	return e.Count < l.limit
}

func (l *LoginLimiter) Failure(key string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := time.Now()
	e := l.entries[key]
	if e.Reset.IsZero() || now.After(e.Reset) {
		e = rateEntry{Reset: now.Add(l.window)}
	}
	e.Count++
	l.entries[key] = e
}

func (l *LoginLimiter) Success(key string) { l.mu.Lock(); defer l.mu.Unlock(); delete(l.entries, key) }
