package state

import (
	"errors"
	"regexp"
	"sort"
	"strings"
	"time"
)

const fleetNodesKey = "fleet.nodes"

var nodeNameRE = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$`)

type FleetNode struct {
	ID          string    `json:"id"`
	Name        string    `json:"name"`
	Address     string    `json:"address"`
	Group       string    `json:"group,omitempty"`
	Environment string    `json:"environment,omitempty"`
	Status      string    `json:"status"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
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
	sort.Slice(nodes, func(i, j int) bool { return strings.ToLower(nodes[i].Name) < strings.ToLower(nodes[j].Name) })
	s.doc.Desired[fleetNodesKey] = nodes
	s.doc.Revision++
	if err := s.persistLocked(); err != nil {
		return FleetNode{}, err
	}
	return node, nil
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
			sort.Slice(out, func(i, j int) bool { return strings.ToLower(out[i].Name) < strings.ToLower(out[j].Name) })
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
		if v, ok := m["id"].(string); ok { node.ID = v }
		if v, ok := m["name"].(string); ok { node.Name = v }
		if v, ok := m["address"].(string); ok { node.Address = v }
		if v, ok := m["group"].(string); ok { node.Group = v }
		if v, ok := m["environment"].(string); ok { node.Environment = v }
		if v, ok := m["status"].(string); ok { node.Status = v }
		if v, ok := m["created_at"].(string); ok { node.CreatedAt, _ = time.Parse(time.RFC3339Nano, v) }
		if v, ok := m["updated_at"].(string); ok { node.UpdatedAt, _ = time.Parse(time.RFC3339Nano, v) }
		if node.Name != "" && node.Address != "" {
			out = append(out, node)
		}
	}
	sort.Slice(out, func(i, j int) bool { return strings.ToLower(out[i].Name) < strings.ToLower(out[j].Name) })
	return out
}
