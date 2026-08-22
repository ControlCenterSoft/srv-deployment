package observability

import "strings"

// ForOperation returns a bounded, newest-first projection of recent audit
// events correlated to one application operation ID.
func (a *AuditLog) ForOperation(operationID string, limit int) ([]AuditEvent, error) {
	operationID = strings.TrimSpace(operationID)
	if operationID == "" {
		return []AuditEvent{}, nil
	}
	if limit <= 0 || limit > 500 {
		limit = 100
	}

	events, err := a.Recent(500)
	if err != nil {
		return nil, err
	}
	out := make([]AuditEvent, 0, limit)
	for _, event := range events {
		if event.OperationID != operationID {
			continue
		}
		out = append(out, event)
		if len(out) == limit {
			break
		}
	}
	return out, nil
}
