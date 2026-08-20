package privileged

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"
)

type fakeRunner struct {
	calls      int
	executable string
	args       []string
	result     CommandResult
	err        error
	wait       time.Duration
}

func (f *fakeRunner) Run(ctx context.Context, executable string, args ...string) (CommandResult, error) {
	f.calls++
	f.executable = executable
	f.args = append([]string(nil), args...)
	if f.wait > 0 {
		select {
		case <-time.After(f.wait):
		case <-ctx.Done():
			return CommandResult{}, ctx.Err()
		}
	}
	return f.result, f.err
}

func newTestEngine(t *testing.T, runner Runner) *Engine {
	t.Helper()
	engine, err := NewEngine(runner, []string{"control-center.service", "nginx.service"}, 50*time.Millisecond)
	if err != nil {
		t.Fatal(err)
	}
	return engine
}

func TestServiceRestartUsesFixedExecutableAndTypedArguments(t *testing.T) {
	runner := &fakeRunner{result: CommandResult{ExitCode: 0, Output: "ok"}}
	engine := newTestEngine(t, runner)

	result, err := engine.Execute(context.Background(), Request{
		ID:      "op-123",
		Type:    OperationServiceRestart,
		ActorID: "user-42",
		Args:    map[string]string{"service": "nginx.service"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if result.Status != "succeeded" {
		t.Fatalf("status=%q", result.Status)
	}
	if runner.executable != "/usr/bin/systemctl" {
		t.Fatalf("executable=%q", runner.executable)
	}
	want := []string{"restart", "--", "nginx.service"}
	if strings.Join(runner.args, "\x00") != strings.Join(want, "\x00") {
		t.Fatalf("args=%q want=%q", runner.args, want)
	}
}

func TestPermissionNegativeRejectsNonAllowlistedServiceWithoutExecution(t *testing.T) {
	runner := &fakeRunner{}
	engine := newTestEngine(t, runner)

	_, err := engine.Execute(context.Background(), Request{
		ID:      "op-1",
		Type:    OperationServiceRestart,
		ActorID: "user-1",
		Args:    map[string]string{"service": "ssh.service"},
	})
	if !errors.Is(err, ErrPermissionDenied) {
		t.Fatalf("error=%v", err)
	}
	if runner.calls != 0 {
		t.Fatalf("runner calls=%d", runner.calls)
	}
}

func TestMalformedServiceCannotInjectArgumentsOrShell(t *testing.T) {
	cases := []string{
		"nginx.service --no-block",
		"nginx.service;id",
		"$(id).service",
		"../nginx.service",
		"nginx",
	}
	for _, service := range cases {
		t.Run(service, func(t *testing.T) {
			runner := &fakeRunner{}
			engine := newTestEngine(t, runner)
			_, err := engine.Execute(context.Background(), Request{
				ID:      "op-2",
				Type:    OperationServiceRestart,
				ActorID: "user-1",
				Args:    map[string]string{"service": service},
			})
			if !errors.Is(err, ErrInvalidRequest) && !errors.Is(err, ErrPermissionDenied) {
				t.Fatalf("error=%v", err)
			}
			if runner.calls != 0 {
				t.Fatalf("runner calls=%d", runner.calls)
			}
		})
	}
}

func TestUnsupportedOperationFailsClosed(t *testing.T) {
	runner := &fakeRunner{}
	engine := newTestEngine(t, runner)

	_, err := engine.Execute(context.Background(), Request{
		ID:      "op-3",
		Type:    "shell.exec",
		ActorID: "user-1",
		Args:    map[string]string{"command": "id"},
	})
	if !errors.Is(err, ErrUnsupportedOperation) {
		t.Fatalf("error=%v", err)
	}
	if runner.calls != 0 {
		t.Fatalf("runner calls=%d", runner.calls)
	}
}

func TestTimeoutIsBoundedAndReported(t *testing.T) {
	runner := &fakeRunner{wait: time.Second}
	engine := newTestEngine(t, runner)

	result, err := engine.Execute(context.Background(), Request{
		ID:      "op-4",
		Type:    OperationServiceRestart,
		ActorID: "user-1",
		Args:    map[string]string{"service": "control-center.service"},
	})
	if !errors.Is(err, ErrTimeout) {
		t.Fatalf("error=%v", err)
	}
	if result.Status != "timeout" {
		t.Fatalf("status=%q", result.Status)
	}
}

func TestOutputIsBounded(t *testing.T) {
	runner := &fakeRunner{result: CommandResult{ExitCode: 0, Output: strings.Repeat("x", maxOutputBytes+100)}}
	engine := newTestEngine(t, runner)

	result, err := engine.Execute(context.Background(), Request{
		ID:      "op-5",
		Type:    OperationServiceRestart,
		ActorID: "user-1",
		Args:    map[string]string{"service": "nginx.service"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Output) > maxOutputBytes+32 {
		t.Fatalf("output too large: %d", len(result.Output))
	}
	if !strings.HasSuffix(result.Output, "...[truncated]") {
		t.Fatalf("output was not marked truncated")
	}
}
