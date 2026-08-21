package state

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"regexp"
	"sort"
	"strings"
	"time"
)

const fleetNodesKey = "fleet.nodes"

var nodeNameRE = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$`)

type FleetNode struct {
	ID                  string     `json:"id"`
	Name                string     `json:"name"`
	Address             string     `json:"address"`
	Group               string     `json:"group,omitempty"`
	Environment         string     `json:"environment,omitempty"`
	Status              string     `json:"status"`
	AgentVersion        string     `json:"agent_version,omitempty"`
	EnrollmentTokenHash string     `json:"enrollment_token_hash,omitempty"`
	EnrollmentExpiresAt *time.Time `json:"enrollment_expires_at,omitempty"`
	EnrolledAt          *time.Time `json:"enrolled_at,omitempty"`
	LastSeenAt          *time.Time `json:"last_seen_at,omitempty"`
	CreatedAt           time.Time  `json:"created_at"`
	UpdatedAt           time.Time  `json:"updated_at"`
}

func (n FleetNode) Public() FleetNode {
	n.EnrollmentTokenHash = ""
	return n
}

func normalizeNodeName(name string) (string, error) {
	name = strings.TrimSpace(name)
	if !nodeNameRE.MatchString(name) {
		return "", errors.New("node name must contain 2-64 letters, digits, dot, underscore or dash")
	}
	return name, nil
}

func normalizeNodeAddress(address string) (string, error) {
	address = strings.TrimSpace(address)
	if address == "" || len(address) > 255 || strings.ContainsAny(address, " \t\r\n/") {
		return "", errors.New("node address must be a hostname or IP address without spaces or path")
	}
	return address, nil
}

func (s *Store) ListFleetNodes() []FleetNode {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return fleetNodesFromDesired(s.doc.Desired)
}

func (s *Store) CreateFleetNode(name, address, group, environment string) (FleetNode, error) {
	name, err := normalizeNodeName(name)
	if err != nil {
		return FleetNode{}, err
	}
	address, err = normalizeNodeAddress(address)
	if err != nil {
		return FleetNode{}, err
	}
	group = strings.TrimSpace(group)
	environment = strings.TrimSpace(environment)
	if len(group) > 64 || len(environment) > 64 {
		return FleetNode{}, errors.New("group and environment must not exceed 64 characters")
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	nodes := fleetNodesFromDesired(s.doc.Desired)
	for _, node := range nodes {
		if strings.EqualFold(node.Name, name) {
			return FleetNode{}, errors.New("node name already exists")
		}
		if strings.EqualFold(node.Address, address) {
			return FleetNode{}, errors.New("node address already exists")
		}
	}
	now := time.Now().UTC()
	node := FleetNode{
		ID: strings.ToLower(name), Name: name, Address: address, Group: group, Environment: environment,
		Status: "pending_enrollment", CreatedAt: now, UpdatedAt: now,
	}
	nodes = append(nodes, node)
	sortFleetNodes(nodes)
	s.doc.Desired[fleetNodesKey] = nodes
	s.doc.Revision++
	if err := s.persistLocked(); err != nil {
		return FleetNode{}, err
	}
	return node.Public(), nil
}

func (s *Store) PrepareFleetEnrollment(id string, ttl time.Duration) (FleetNode, string, error) {
	id = strings.TrimSpace(strings.ToLower(id))
	if id == "" {
		return FleetNode{}, "", errors.New("node id is required")
	}
	if ttl <= 0 || ttl > 24*time.Hour {
		return FleetNode{}, "", errors.New("enrollment ttl must be between 1 second and 24 hours")
	}
	secret := make([]byte, 32)
	if _, err := rand.Read(secret); err != nil {
		return FleetNode{}, "", err
	}
	token := base64.RawURLEncoding.EncodeToString(secret)
	digest := sha256.Sum256([]byte(token))

	s.mu.Lock()
	defer s.mu.Unlock()
	nodes := fleetNodesFromDesired(s.doc.Desired)
	idx := fleetNodeIndex(nodes, id)
	if idx < 0 {
		return FleetNode{}, "", errors.New("fleet node not found")
	}
	now := time.Now().UTC()
	expires := now.Add(ttl)
	nodes[idx].EnrollmentTokenHash = hex.EncodeToString(digest[:])
	nodes[idx].EnrollmentExpiresAt = &expires
	nodes[idx].Status = "enrollment_ready"
	nodes[idx].UpdatedAt = now
	s.doc.Desired[fleetNodesKey] = nodes
	s.doc.Revision++
	if err := s.persistLocked(); err != nil {
		return FleetNode{}, "", err
	}
	return nodes[idx].Public(), token, nil
}

func (s *Store) EnrollFleetNode(id, token, agentVersion string) (FleetNode, error) {
	id = strings.TrimSpace(strings.ToLower(id))
	token = strings.TrimSpace(token)
	agentVersion = strings.TrimSpace(agentVersion)
	if id == "" || token == "" {
		return FleetNode{}, errors.New("node id and enrollment token are required")
	}
	if len(agentVersion) > 64 || strings.ContainsAny(agentVersion, "\r\n\t") {
		return FleetNode{}, errors.New("invalid agent version")
	}
	digest := sha256.Sum256([]byte(token))
	providedHash := hex.EncodeToString(digest[:])

	s.mu.Lock()
	defer s.mu.Unlock()
	nodes := fleetNodesFromDesired(s.doc.Desired)
	idx := fleetNodeIndex(nodes, id)
	if idx < 0 {
		return FleetNode{}, errors.New("invalid or expired enrollment credential")
	}
	node := &nodes[idx]
	now := time.Now().UTC()
	if node.Status != "enrollment_ready" || node.EnrollmentTokenHash == "" || node.EnrollmentExpiresAt == nil || !now.Before(*node.EnrollmentExpiresAt) {
		return FleetNode{}, errors.New("invalid or expired enrollment credential")
	}
	if subtle.ConstantTimeCompare([]byte(node.EnrollmentTokenHash), []byte(providedHash)) != 1 {
		return FleetNode{}, errors.New("invalid or expired enrollment credential")
	}
	node.Status = "enrolled"
	node.AgentVersion = agentVersion
	node.EnrollmentTokenHash = ""
	node.EnrollmentExpiresAt = nil
	node.EnrolledAt = &now
	node.LastSeenAt = &now
	node.UpdatedAt = now
	s.doc.Desired[fleetNodesKey] = nodes
	s.doc.Revision++
	if err := s.persistLocked(); err != nil {
		return FleetNode{}, err
	}
	return node.Public(), nil
}

func fleetNodeIndex(nodes []FleetNode, id string) int {
	for i := range nodes {
		if strings.EqualFold(nodes[i].ID, id) {
			return i
		}
	}
	return -1
}

func sortFleetNodes(nodes []FleetNode) {
	sort.Slice(nodes, func(i, j int) bool { return strings.ToLower(nodes[i].Name) < strings.ToLower(nodes[j].Name) })
}

func fleetNodesFromDesired(desired map[string]any) []FleetNode {
	raw, ok := desired[fleetNodesKey]
	if !ok || raw == nil {
		return []FleetNode{}
	}
	items, ok := raw.([]any)
	if !ok {
		if typed, ok := raw.([]FleetNode); ok {
			out := append([]FleetNode(nil), typed...)
			sortFleetNodes(out)
			return out
		}
		return []FleetNode{}
	}
	out := make([]FleetNode, 0, len(items))
	for _, item := range items {
		m, ok := item.(map[string]any)
		if !ok {
			continue
		}
		node := FleetNode{}
		if v, ok := m["id"].(string); ok {
			node.ID = v
		}
		if v, ok := m["name"].(string); ok {
			node.Name = v
		}
		if v, ok := m["address"].(string); ok {
			node.Address = v
		}
		if v, ok := m["group"].(string); ok {
			node.Group = v
		}
		if v, ok := m["environment"].(string); ok {
			node.Environment = v
		}
		if v, ok := m["status"].(string); ok {
			node.Status = v
		}
		if v, ok := m["agent_version"].(string); ok {
			node.AgentVersion = v
		}
		if v, ok := m["enrollment_token_hash"].(string); ok {
			node.EnrollmentTokenHash = v
		}
		if v, ok := m["enrollment_expires_at"].(string); ok {
			if parsed, err := time.Parse(time.RFC3339Nano, v); err == nil {
				node.EnrollmentExpiresAt = &parsed
			}
		}
		if v, ok := m["enrolled_at"].(string); ok {
			if parsed, err := time.Parse(time.RFC3339Nano, v); err == nil {
				node.EnrolledAt = &parsed
			}
		}
		if v, ok := m["last_seen_at"].(string); ok {
			if parsed, err := time.Parse(time.RFC3339Nano, v); err == nil {
				node.LastSeenAt = &parsed
			}
		}
		if v, ok := m["created_at"].(string); ok {
			node.CreatedAt, _ = time.Parse(time.RFC3339Nano, v)
		}
		if v, ok := m["updated_at"].(string); ok {
			node.UpdatedAt, _ = time.Parse(time.RFC3339Nano, v)
		}
		if node.Name != "" && node.Address != "" {
			out = append(out, node)
		}
	}
	sortFleetNodes(out)
	return out
}
