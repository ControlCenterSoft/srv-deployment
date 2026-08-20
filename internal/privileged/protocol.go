package privileged

import (
	"errors"
	"regexp"
	"strings"
)

const SchemaVersion = 1

const (
	ActionSystemdStatus  = "systemd.unit.status"
	ActionSystemdRestart = "systemd.unit.restart"
)

var operationIDPattern = regexp.MustCompile(`^[a-f0-9]{32}$`)
var unitPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9_.@:-]{0,127}\.service$`)

type Request struct {
	Schema      int    `json:"schema"`
	OperationID string `json:"operation_id"`
	Action      string `json:"action"`
	Target      string `json:"target"`
}

type Result struct {
	Unit        string `json:"unit,omitempty"`
	LoadState   string `json:"load_state,omitempty"`
	ActiveState string `json:"active_state,omitempty"`
	SubState    string `json:"sub_state,omitempty"`
}

type Error struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type Response struct {
	Schema      int     `json:"schema"`
	OperationID string  `json:"operation_id"`
	Status      string  `json:"status"`
	Result      *Result `json:"result,omitempty"`
	Error       *Error  `json:"error,omitempty"`
}

func (r Request) Validate() error {
	if r.Schema != SchemaVersion {
		return errors.New("unsupported schema")
	}
	if !operationIDPattern.MatchString(r.OperationID) {
		return errors.New("invalid operation id")
	}
	switch r.Action {
	case ActionSystemdStatus, ActionSystemdRestart:
	default:
		return errors.New("unsupported action")
	}
	if !unitPattern.MatchString(r.Target) || strings.ContainsAny(r.Target, "/\\\x00\r\n\t ") {
		return errors.New("invalid target")
	}
	return nil
}

func ParseAllowedActions(raw string) ([]string, error) {
	parts := strings.Split(raw, ",")
	actions := make([]string, 0, len(parts))
	seen := map[string]struct{}{}
	for _, part := range parts {
		action := strings.TrimSpace(part)
		if action == "" {
			continue
		}
		switch action {
		case ActionSystemdStatus, ActionSystemdRestart:
		default:
			return nil, errors.New("unsupported allowed action")
		}
		if _, ok := seen[action]; ok {
			continue
		}
		seen[action] = struct{}{}
		actions = append(actions, action)
	}
	if len(actions) == 0 {
		return nil, errors.New("no allowed actions configured")
	}
	return actions, nil
}
