//go:build linux

package privileged

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"syscall"
)

// JSONLAuditSink пишет по одному нормализованному AuditEvent на строку.
// O_NOFOLLOW исключает подмену audit-файла симлинком; O_SYNC обеспечивает,
// что RecordDurable возвращает успех только после синхронной записи.
type JSONLAuditSink struct {
	path string
	mu   sync.Mutex
}

func NewJSONLAuditSink(path string) (*JSONLAuditSink, error) {
	if path == "" || !filepath.IsAbs(path) {
		return nil, fmt.Errorf("audit path must be absolute")
	}
	parent := filepath.Dir(path)
	info, err := os.Stat(parent)
	if err != nil {
		return nil, fmt.Errorf("audit directory: %w", err)
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("audit parent is not a directory")
	}
	if info.Mode().Perm()&0022 != 0 {
		return nil, fmt.Errorf("audit directory is group/world writable")
	}
	return &JSONLAuditSink{path: path}, nil
}

func (s *JSONLAuditSink) Ready() error {
	if s == nil {
		return fmt.Errorf("audit sink is nil")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	file, err := s.open()
	if err != nil {
		return err
	}
	return file.Close()
}

func (s *JSONLAuditSink) RecordDurable(event AuditEvent) error {
	if s == nil {
		return fmt.Errorf("audit sink is nil")
	}
	payload, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("encode audit event: %w", err)
	}
	payload = append(payload, '\n')

	s.mu.Lock()
	defer s.mu.Unlock()
	file, err := s.open()
	if err != nil {
		return err
	}
	defer file.Close()
	if _, err := file.Write(payload); err != nil {
		return fmt.Errorf("write audit event: %w", err)
	}
	if err := file.Sync(); err != nil {
		return fmt.Errorf("sync audit event: %w", err)
	}
	return nil
}

func (s *JSONLAuditSink) open() (*os.File, error) {
	fd, err := syscall.Open(s.path, syscall.O_WRONLY|syscall.O_CREAT|syscall.O_APPEND|syscall.O_CLOEXEC|syscall.O_NOFOLLOW|syscall.O_SYNC, 0600)
	if err != nil {
		return nil, fmt.Errorf("open audit log: %w", err)
	}
	file := os.NewFile(uintptr(fd), s.path)
	if file == nil {
		syscall.Close(fd)
		return nil, fmt.Errorf("open audit log: invalid descriptor")
	}
	info, err := file.Stat()
	if err != nil {
		file.Close()
		return nil, fmt.Errorf("stat audit log: %w", err)
	}
	if !info.Mode().IsRegular() || info.Mode().Perm()&0077 != 0 {
		file.Close()
		return nil, fmt.Errorf("audit log must be a regular 0600 file")
	}
	return file, nil
}
