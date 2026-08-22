package operations

import "sort"

// Incidents returns a bounded, newest-first projection of abnormal terminal
// operations. Successful and currently-running operations are intentionally
// excluded so callers can consume an operator-focused incident feed without
// changing the underlying operation schema.
func (s *Store) Incidents(limit int) []Record {
	if limit <= 0 || limit > 500 {
		limit = 100
	}

	s.mu.RLock()
	defer s.mu.RUnlock()

	out := make([]Record, 0, limit)
	for _, rec := range s.doc.Records {
		if rec.Status != StatusFailed && rec.Status != StatusInterrupted {
			continue
		}
		out = append(out, rec)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].StartedAt.Equal(out[j].StartedAt) {
			return out[i].ID > out[j].ID
		}
		return out[i].StartedAt.After(out[j].StartedAt)
	})
	if len(out) > limit {
		out = out[:limit]
	}
	return out
}
