package state

import (
	"errors"
	"strings"
	"time"
)

// DisconnectFleetNode revokes all active enrollment/agent credentials while
// preserving the managed node inventory record so it can be safely re-enrolled.
// The operation is idempotent and never changes the remote host itself.
func (s *Store) DisconnectFleetNode(id string) (FleetNode, bool, error) {
	id = strings.TrimSpace(strings.ToLower(id))
	if id == "" {
		return FleetNode{}, false, errors.New("node id is required")
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	nodes := fleetNodesFromDesired(s.doc.Desired)
	idx := fleetNodeIndex(nodes, id)
	if idx < 0 {
		return FleetNode{}, false, errors.New("fleet node not found")
	}

	node := &nodes[idx]
	changed := node.Status != "pending_enrollment" ||
		node.EnrollmentTokenHash != "" || node.EnrollmentExpiresAt != nil ||
		node.AgentCredentialHash != "" || node.EnrolledAt != nil || node.LastSeenAt != nil ||
		node.AgentVersion != "" || node.Hostname != "" || node.OSName != "" ||
		node.OSVersion != "" || node.Architecture != ""
	if !changed {
		return node.Public(), false, nil
	}

	node.Status = "pending_enrollment"
	node.EnrollmentTokenHash = ""
	node.EnrollmentExpiresAt = nil
	node.AgentCredentialHash = ""
	node.EnrolledAt = nil
	node.LastSeenAt = nil
	node.AgentVersion = ""
	node.Hostname = ""
	node.OSName = ""
	node.OSVersion = ""
	node.Architecture = ""
	node.UpdatedAt = time.Now().UTC()

	s.doc.Desired[fleetNodesKey] = nodes
	s.doc.Revision++
	if err := s.persistLocked(); err != nil {
		return FleetNode{}, false, err
	}
	return node.Public(), true, nil
}
