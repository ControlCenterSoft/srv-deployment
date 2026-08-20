package privileged

import "time"

// AuditEvent связывает privileged operation с operation/actor identity без
// сохранения произвольного payload или вывода команды.
type AuditEvent struct {
	OperationID string    `json:"operation_id"`
	ActorID     string    `json:"actor_id"`
	Type        string    `json:"type"`
	Status      string    `json:"status"`
	ExitCode    int       `json:"exit_code"`
	ErrorCode   string    `json:"error_code,omitempty"`
	StartedAt   time.Time `json:"started_at"`
	FinishedAt  time.Time `json:"finished_at"`
	DurationMS  int64     `json:"duration_ms"`
}

// AuditSink принимает нормализованные события и обязан подтверждать их
// устойчивую запись до возврата nil. Ошибка sink обрабатывается fail-closed
// на границе privileged worker.
type AuditSink interface {
	Record(AuditEvent) error
}

// AuditSinkFunc сохраняет совместимый удобный adapter для in-memory tests.
type AuditSinkFunc func(AuditEvent)

func (f AuditSinkFunc) Record(event AuditEvent) error {
	if f != nil {
		f(event)
	}
	return nil
}
