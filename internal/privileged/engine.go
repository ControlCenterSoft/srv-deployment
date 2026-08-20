package privileged

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"slices"
	"strings"
	"time"
)

const (
	OperationServiceRestart = "service.restart"
	maxOutputBytes          = 4096
)

var (
	ErrUnsupportedOperation = errors.New("unsupported privileged operation")
	ErrPermissionDenied     = errors.New("privileged operation permission denied")
	ErrInvalidRequest       = errors.New("invalid privileged operation request")
	ErrTimeout              = errors.New("privileged operation timed out")
	serviceNameRE           = regexp.MustCompile(`^[A-Za-z0-9_.@-]{1,128}\.service$`)
)

type Request struct {
	ID      string            `json:"id"`
	Type    string            `json:"type"`
	ActorID string            `json:"actor_id"`
	Args    map[string]string `json:"args"`
}

type Result struct {
	ID       string `json:"id"`
	Type     string `json:"type"`
	Status   string `json:"status"`
	ExitCode int    `json:"exit_code"`
	Output   string `json:"output,omitempty"`
}

type CommandResult struct {
	ExitCode int
	Output   string
}

type Runner interface {
	Run(ctx context.Context, executable string, args ...string) (CommandResult, error)
}

type Engine struct {
	runner          Runner
	allowedServices []string
	timeout         time.Duration
}

func NewEngine(runner Runner, allowedServices []string, timeout time.Duration) (*Engine, error) {
	if runner == nil {
		return nil, fmt.Errorf("%w: runner is required", ErrInvalidRequest)
	}
	if timeout <= 0 || timeout > 30*time.Second {
		return nil, fmt.Errorf("%w: timeout must be within (0,30s]", ErrInvalidRequest)
	}
	if len(allowedServices) == 0 {
		return nil, fmt.Errorf("%w: allowed service list is empty", ErrInvalidRequest)
	}

	normalized := make([]string, 0, len(allowedServices))
	seen := map[string]struct{}{}
	for _, service := range allowedServices {
		if !serviceNameRE.MatchString(service) {
			return nil, fmt.Errorf("%w: invalid allowlisted service %q", ErrInvalidRequest, service)
		}
		if _, ok := seen[service]; ok {
			continue
		}
		seen[service] = struct{}{}
		normalized = append(normalized, service)
	}
	slices.Sort(normalized)

	return &Engine{
		runner:          runner,
		allowedServices: normalized,
		timeout:         timeout,
	}, nil
}

func (e *Engine) Execute(ctx context.Context, req Request) (Result, error) {
	result := Result{ID: req.ID, Type: req.Type, Status: "failed", ExitCode: -1}

	if !validOpaqueID(req.ID) || !validOpaqueID(req.ActorID) {
		return result, fmt.Errorf("%w: id and actor_id must be non-empty opaque identifiers", ErrInvalidRequest)
	}
	if req.Type != OperationServiceRestart {
		return result, fmt.Errorf("%w: %s", ErrUnsupportedOperation, req.Type)
	}
	if len(req.Args) != 1 {
		return result, fmt.Errorf("%w: service.restart requires exactly one argument", ErrInvalidRequest)
	}

	service, ok := req.Args["service"]
	if !ok || !serviceNameRE.MatchString(service) {
		return result, fmt.Errorf("%w: invalid service", ErrInvalidRequest)
	}
	if !slices.Contains(e.allowedServices, service) {
		return result, fmt.Errorf("%w: service %q is not allowlisted", ErrPermissionDenied, service)
	}

	runCtx, cancel := context.WithTimeout(ctx, e.timeout)
	defer cancel()

	commandResult, err := e.runner.Run(runCtx, "/usr/bin/systemctl", "restart", "--", service)
	result.ExitCode = commandResult.ExitCode
	result.Output = boundedOutput(commandResult.Output)

	if errors.Is(runCtx.Err(), context.DeadlineExceeded) || errors.Is(err, context.DeadlineExceeded) {
		result.Status = "timeout"
		return result, ErrTimeout
	}
	if err != nil {
		return result, fmt.Errorf("service restart failed: %w", err)
	}
	if commandResult.ExitCode != 0 {
		return result, fmt.Errorf("service restart failed with exit code %d", commandResult.ExitCode)
	}

	result.Status = "succeeded"
	return result, nil
}

func validOpaqueID(value string) bool {
	if len(value) < 1 || len(value) > 128 {
		return false
	}
	for _, r := range value {
		if r <= 0x20 || r == 0x7f {
			return false
		}
	}
	return true
}

func boundedOutput(value string) string {
	value = strings.TrimSpace(value)
	if len(value) <= maxOutputBytes {
		return value
	}
	return value[:maxOutputBytes] + "...[truncated]"
}
