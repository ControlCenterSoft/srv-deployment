package observability

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const maxReadBytes int64 = 2 << 20

type AuditEvent struct {
	Time        time.Time `json:"time"`
	OperationID string    `json:"operation_id"`
	Actor       string    `json:"actor,omitempty"`
	Role        string    `json:"role,omitempty"`
	Action      string    `json:"action"`
	Target      string    `json:"target,omitempty"`
	Result      string    `json:"result"`
	RemoteIP    string    `json:"remote_ip,omitempty"`
	ErrorCode   string    `json:"error_code,omitempty"`
}

type AuditLog struct {
	mu   sync.Mutex
	path string
}

func OpenAudit(dir string) (*AuditLog, error) {
	if strings.TrimSpace(dir) == "" {
		return nil, errors.New("audit directory is required")
	}
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return nil, fmt.Errorf("create audit directory: %w", err)
	}
	path := filepath.Join(dir, "audit.jsonl")
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o640)
	if err != nil {
		return nil, fmt.Errorf("open audit log: %w", err)
	}
	if err := f.Chmod(0o640); err != nil {
		_ = f.Close()
		return nil, err
	}
	if err := f.Close(); err != nil {
		return nil, err
	}
	return &AuditLog{path: path}, nil
}

func (a *AuditLog) Append(event AuditEvent) error {
	if strings.TrimSpace(event.Action) == "" || strings.TrimSpace(event.Result) == "" {
		return errors.New("audit action and result are required")
	}
	if event.Time.IsZero() {
		event.Time = time.Now().UTC()
	}
	b, err := json.Marshal(event)
	if err != nil {
		return err
	}
	b = append(b, '\n')
	a.mu.Lock()
	defer a.mu.Unlock()
	f, err := os.OpenFile(a.path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o640)
	if err != nil {
		return err
	}
	defer f.Close()
	if _, err := f.Write(b); err != nil {
		return err
	}
	return f.Sync()
}

func (a *AuditLog) Recent(limit int) ([]AuditEvent, error) {
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	f, err := os.Open(a.path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return []AuditEvent{}, nil
		}
		return nil, err
	}
	defer f.Close()
	stat, err := f.Stat()
	if err != nil {
		return nil, err
	}
	start := stat.Size() - maxReadBytes
	if start < 0 {
		start = 0
	}
	if _, err := f.Seek(start, io.SeekStart); err != nil {
		return nil, err
	}
	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 64*1024), 256*1024)
	if start > 0 {
		_ = scanner.Scan()
	}
	events := make([]AuditEvent, 0, limit)
	for scanner.Scan() {
		var event AuditEvent
		if err := json.Unmarshal(scanner.Bytes(), &event); err != nil {
			continue
		}
		events = append(events, event)
		if len(events) > limit {
			events = events[len(events)-limit:]
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	for i, j := 0, len(events)-1; i < j; i, j = i+1, j-1 {
		events[i], events[j] = events[j], events[i]
	}
	return events, nil
}
