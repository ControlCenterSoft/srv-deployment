package privileged

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

const maxOutputBytes = 8 << 10

type CommandExecutor interface {
	Run(ctx context.Context, path string, args ...string) ([]byte, error)
}

type OSExecutor struct{}

func (OSExecutor) Run(ctx context.Context, path string, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, path, args...)
	cmd.Env = []string{"PATH=/usr/bin:/bin", "LANG=C", "LC_ALL=C"}
	out, err := cmd.CombinedOutput()
	if len(out) > maxOutputBytes {
		out = out[:maxOutputBytes]
	}
	return out, err
}

type Runner struct {
	SystemctlPath  string
	AllowedUnits   map[string]struct{}
	AllowedActions map[string]struct{}
	Timeout        time.Duration
	Exec           CommandExecutor
}

func NewRunner(allowedUnits, allowedActions []string) (*Runner, error) {
	units := make(map[string]struct{}, len(allowedUnits))
	for _, unit := range allowedUnits {
		req := Request{Schema: SchemaVersion, OperationID: strings.Repeat("a", 32), Action: ActionSystemdStatus, Target: strings.TrimSpace(unit)}
		if err := req.Validate(); err != nil {
			return nil, fmt.Errorf("invalid allowed unit %q: %w", unit, err)
		}
		units[req.Target] = struct{}{}
	}
	if len(units) == 0 {
		return nil, errors.New("at least one allowed systemd unit is required")
	}
	actions := make(map[string]struct{}, len(allowedActions))
	for _, action := range allowedActions {
		switch action {
		case ActionSystemdStatus, ActionSystemdRestart:
			actions[action] = struct{}{}
		default:
			return nil, fmt.Errorf("invalid allowed action %q", action)
		}
	}
	if len(actions) == 0 {
		return nil, errors.New("at least one allowed action is required")
	}
	return &Runner{SystemctlPath: "/usr/bin/systemctl", AllowedUnits: units, AllowedActions: actions, Timeout: 5 * time.Second, Exec: OSExecutor{}}, nil
}

func (r *Runner) Execute(ctx context.Context, req Request) Response {
	resp := Response{Schema: SchemaVersion, OperationID: req.OperationID}
	if err := req.Validate(); err != nil {
		resp.Status = "rejected"
		resp.Error = &Error{Code: "invalid_request", Message: err.Error()}
		return resp
	}
	if _, ok := r.AllowedActions[req.Action]; !ok {
		resp.Status = "rejected"
		resp.Error = &Error{Code: "action_not_allowed", Message: "action is not allowlisted"}
		return resp
	}
	if _, ok := r.AllowedUnits[req.Target]; !ok {
		resp.Status = "rejected"
		resp.Error = &Error{Code: "target_not_allowed", Message: "target is not allowlisted"}
		return resp
	}
	timeout := r.Timeout
	if timeout <= 0 || timeout > 30*time.Second {
		timeout = 5 * time.Second
	}
	runCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	switch req.Action {
	case ActionSystemdStatus:
		out, err := r.Exec.Run(runCtx, r.SystemctlPath, "show", "--no-pager", "--property=Id,LoadState,ActiveState,SubState", "--", req.Target)
		if err != nil {
			return commandFailure(resp, runCtx)
		}
		result, err := parseSystemdShow(out, req.Target)
		if err != nil {
			resp.Status = "failed"
			resp.Error = &Error{Code: "invalid_systemd_response", Message: err.Error()}
			return resp
		}
		resp.Status = "succeeded"
		resp.Result = &result
		return resp
	case ActionSystemdRestart:
		if _, err := r.Exec.Run(runCtx, r.SystemctlPath, "restart", "--no-block", "--", req.Target); err != nil {
			return commandFailure(resp, runCtx)
		}
		resp.Status = "succeeded"
		resp.Result = &Result{Unit: req.Target}
		return resp
	default:
		resp.Status = "rejected"
		resp.Error = &Error{Code: "action_not_allowed", Message: "action is not allowlisted"}
		return resp
	}
}

func commandFailure(resp Response, ctx context.Context) Response {
	resp.Status = "failed"
	if errors.Is(ctx.Err(), context.DeadlineExceeded) {
		resp.Error = &Error{Code: "operation_timeout", Message: "privileged operation timed out"}
		return resp
	}
	resp.Error = &Error{Code: "systemd_command_failed", Message: "systemd operation failed"}
	return resp
}

func parseSystemdShow(out []byte, expectedUnit string) (Result, error) {
	values := map[string]string{}
	for _, line := range strings.Split(string(out), "\n") {
		if line == "" {
			continue
		}
		key, value, ok := strings.Cut(line, "=")
		if !ok {
			return Result{}, errors.New("malformed systemctl output")
		}
		values[key] = value
	}
	if values["Id"] != expectedUnit {
		return Result{}, errors.New("systemd unit identity mismatch")
	}
	if values["LoadState"] == "" || values["ActiveState"] == "" || values["SubState"] == "" {
		return Result{}, errors.New("incomplete systemctl output")
	}
	return Result{Unit: values["Id"], LoadState: values["LoadState"], ActiveState: values["ActiveState"], SubState: values["SubState"]}, nil
}
