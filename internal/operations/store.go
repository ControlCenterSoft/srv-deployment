package operations

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"
)

const (
	SchemaVersion = 1
	maxRecords    = 1000
)

type Status string

const (
	StatusRunning     Status = "running"
	StatusSucceeded   Status = "succeeded"
	StatusFailed      Status = "failed"
	StatusInterrupted Status = "interrupted"
)

type Record struct {
	ID         string     `json:"id"`
	Kind       string     `json:"kind"`
	Actor      string     `json:"actor"`
	Role       string     `json:"role"`
	Target     string     `json:"target,omitempty"`
	Status     Status     `json:"status"`
	StartedAt  time.Time  `json:"started_at"`
	FinishedAt *time.Time `json:"finished_at,omitempty"`
	ErrorCode  string     `json:"error_code,omitempty"`
}

type document struct {
	Schema  int               `json:"schema"`
	Records map[string]Record `json:"records"`
}

type Store struct {
	mu   sync.RWMutex
	path string
	doc  document
}

func Open(dir string) (*Store, error) {
	if dir == "" {
		return nil, errors.New("operations directory is required")
	}
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return nil, fmt.Errorf("create operations directory: %w", err)
	}
	s := &Store{path: filepath.Join(dir, "operations.json"), doc: document{Schema: SchemaVersion, Records: map[string]Record{}}}
	if b, err := os.ReadFile(s.path); err == nil {
		if err := json.Unmarshal(b, &s.doc); err != nil {
			return nil, fmt.Errorf("decode operations: %w", err)
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return nil, fmt.Errorf("read operations: %w", err)
	}
	if s.doc.Schema != SchemaVersion {
		return nil, fmt.Errorf("unsupported operations schema: %d", s.doc.Schema)
	}
	if s.doc.Records == nil {
		s.doc.Records = map[string]Record{}
	}
	changed := false
	now := time.Now().UTC()
	for id, rec := range s.doc.Records {
		if rec.Status == StatusRunning {
			rec.Status = StatusInterrupted
			rec.FinishedAt = &now
			rec.ErrorCode = "process_restarted"
			s.doc.Records[id] = rec
			changed = true
		}
	}
	if changed {
		if err := s.persistLocked(); err != nil {
			return nil, err
		}
	}
	return s, nil
}

func (s *Store) Start(id, kind, actor, role, target string) (Record, error) {
	if id == "" || kind == "" || actor == "" {
		return Record{}, errors.New("operation id, kind and actor are required")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, exists := s.doc.Records[id]; exists {
		return Record{}, errors.New("operation already exists")
	}
	rec := Record{ID: id, Kind: kind, Actor: actor, Role: role, Target: target, Status: StatusRunning, StartedAt: time.Now().UTC()}
	s.doc.Records[id] = rec
	s.pruneLocked()
	if err := s.persistLocked(); err != nil {
		delete(s.doc.Records, id)
		return Record{}, err
	}
	return rec, nil
}

func (s *Store) Finish(id string, status Status, errorCode string) (Record, error) {
	if status != StatusSucceeded && status != StatusFailed {
		return Record{}, errors.New("invalid terminal operation status")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	rec, ok := s.doc.Records[id]
	if !ok {
		return Record{}, errors.New("operation not found")
	}
	if rec.Status != StatusRunning {
		return Record{}, errors.New("operation is already terminal")
	}
	now := time.Now().UTC()
	rec.Status = status
	rec.FinishedAt = &now
	rec.ErrorCode = errorCode
	s.doc.Records[id] = rec
	if err := s.persistLocked(); err != nil {
		return Record{}, err
	}
	return rec, nil
}

func (s *Store) List(limit int) []Record {
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]Record, 0, len(s.doc.Records))
	for _, rec := range s.doc.Records {
		out = append(out, rec)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].StartedAt.After(out[j].StartedAt) })
	if len(out) > limit {
		out = out[:limit]
	}
	return out
}

func (s *Store) Count() int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return len(s.doc.Records)
}

func (s *Store) pruneLocked() {
	if len(s.doc.Records) <= maxRecords {
		return
	}
	all := make([]Record, 0, len(s.doc.Records))
	for _, rec := range s.doc.Records {
		all = append(all, rec)
	}
	sort.Slice(all, func(i, j int) bool { return all[i].StartedAt.Before(all[j].StartedAt) })
	remove := len(all) - maxRecords
	for i := 0; i < remove; i++ {
		delete(s.doc.Records, all[i].ID)
	}
}

func (s *Store) persistLocked() error {
	b, err := json.MarshalIndent(s.doc, "", "  ")
	if err != nil {
		return err
	}
	return atomicWrite(s.path, append(b, '\n'), 0o600)
}

func atomicWrite(path string, data []byte, mode os.FileMode) error {
	f, err := os.CreateTemp(filepath.Dir(path), ".tmp-operations-*")
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
