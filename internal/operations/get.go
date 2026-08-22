package operations

// Get returns the operation with the exact identifier without mutating store state.
func (s *Store) Get(id string) (Record, bool) {
	if id == "" {
		return Record{}, false
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	rec, ok := s.doc.Records[id]
	return rec, ok
}
