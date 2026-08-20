//go:build linux

package privileged

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sync"
	"syscall"
)

const maxAuditEventBytes = 4096

// JSONLAuditSink хранит append-only JSONL audit. Каждый успешный Begin/Record
// завершается fsync, поэтому nil означает устойчивую запись события.
type JSONLAuditSink struct {
	mu   sync.Mutex
	file *os.File
}

func NewJSONLAuditSink(path string) (*JSONLAuditSink, error) {
	if path == "" || !filepath.IsAbs(path) {
		return nil, fmt.Errorf("audit path must be absolute")
	}
	parent := filepath.Dir(path)
	info, err := os.Stat(parent)
	if err != nil {
		return nil, fmt.Errorf("audit parent: %w", err)
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("audit parent is not a directory")
	}

	fd, err := syscall.Open(path, syscall.O_WRONLY|syscall.O_APPEND|syscall.O_CREAT|syscall.O_CLOEXEC|syscall.O_NOFOLLOW, 0600)
	if err != nil {
		return nil, fmt.Errorf("open audit log: %w", err)
	}
	file := os.NewFile(uintptr(fd), path)
	if file == nil {
		_ = syscall.Close(fd)
		return nil, errors.New("open audit log: invalid file descriptor")
	}
	fail := func(err error) (*JSONLAuditSink, error) {
		_ = file.Close()
		return nil, err
	}
	if err := file.Chmod(0600); err != nil {
		return fail(fmt.Errorf("chmod audit log: %w", err))
	}
	stat, err := file.Stat()
	if err != nil {
		return fail(fmt.Errorf("stat audit log: %w", err))
	}
	if !stat.Mode().IsRegular() {
		return fail(fmt.Errorf("audit log must be a regular file"))
	}
	return &JSONLAuditSink{file: file}, nil
}

// Begin durably records execution intent before a privileged command may run.
func (s *JSONLAuditSink) Begin(event AuditEvent) error {
	return s.append(event)
}

// Record durably records the terminal outcome.
func (s *JSONLAuditSink) Record(event AuditEvent) error {
	return s.append(event)
}

func (s *JSONLAuditSink) append(event AuditEvent) error {
	if s == nil {
		return errors.New("audit sink is closed")
	}
	payload, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("encode audit event: %w", err)
	}
	if len(payload) > maxAuditEventBytes {
		return fmt.Errorf("audit event exceeds %d bytes", maxAuditEventBytes)
	}
	payload = append(payload, '\n')

	s.mu.Lock()
	defer s.mu.Unlock()
	if s.file == nil {
		return errors.New("audit sink is closed")
	}
	n, err := s.file.Write(payload)
	if err != nil {
		return fmt.Errorf("append audit event: %w", err)
	}
	if n != len(payload) {
		return io.ErrShortWrite
	}
	if err := s.file.Sync(); err != nil {
		return fmt.Errorf("sync audit event: %w", err)
	}
	return nil
}

func (s *JSONLAuditSink) Close() error {
	if s == nil {
		return nil
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.file == nil {
		return nil
	}
	err := s.file.Close()
	s.file = nil
	return err
}
