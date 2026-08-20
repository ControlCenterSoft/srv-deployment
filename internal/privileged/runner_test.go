package privileged

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"
)

type fakeExec struct {
	path  string
	args  []string
	out   []byte
	err   error
	block bool
}

func (f *fakeExec) Run(ctx context.Context, path string, args ...string) ([]byte, error) {
	f.path = path
	f.args = append([]string(nil), args...)
	if f.block {
		<-ctx.Done()
		return nil, ctx.Err()
	}
	return f.out, f.err
}

func validRequest(action, target string) Request {
	return Request{Schema: SchemaVersion, OperationID: strings.Repeat("a", 32), Action: action, Target: target}
}

func TestRunnerStatusUsesFixedSystemctlArguments(t *testing.T) {
	runner, err := NewRunner([]string{"control-center.service"}, []string{ActionSystemdStatus, ActionSystemdRestart})
	if err != nil {
		t.Fatal(err)
	}
	fake := &fakeExec{out: []byte("Id=control-center.service\nLoadState=loaded\nActiveState=active\nSubState=running\n")}
	runner.Exec = fake
	resp := runner.Execute(context.Background(), validRequest(ActionSystemdStatus, "control-center.service"))
	if resp.Status != "succeeded" {
		t.Fatalf("response=%+v", resp)
	}
	if fake.path != "/usr/bin/systemctl" {
		t.Fatalf("path=%q", fake.path)
	}
	want := []string{"show", "--no-pager", "--property=Id,LoadState,ActiveState,SubState", "--", "control-center.service"}
	if strings.Join(fake.args, "\x00") != strings.Join(want, "\x00") {
		t.Fatalf("args=%q", fake.args)
	}
	if resp.Result == nil || resp.Result.ActiveState != "active" {
		t.Fatalf("result=%+v", resp.Result)
	}
}

func TestRunnerRejectsTargetInjectionBeforeExecutor(t *testing.T) {
	runner, _ := NewRunner([]string{"control-center.service"}, []string{ActionSystemdStatus, ActionSystemdRestart})
	fake := &fakeExec{}
	runner.Exec = fake
	resp := runner.Execute(context.Background(), validRequest(ActionSystemdRestart, "control-center.service;id.service"))
	if resp.Status != "rejected" || resp.Error == nil || resp.Error.Code != "invalid_request" {
		t.Fatalf("response=%+v", resp)
	}
	if fake.path != "" {
		t.Fatal("executor should not be called")
	}
}

func TestRunnerRejectsNonAllowlistedUnit(t *testing.T) {
	runner, _ := NewRunner([]string{"control-center.service"}, []string{ActionSystemdStatus, ActionSystemdRestart})
	fake := &fakeExec{}
	runner.Exec = fake
	resp := runner.Execute(context.Background(), validRequest(ActionSystemdRestart, "ssh.service"))
	if resp.Error == nil || resp.Error.Code != "target_not_allowed" {
		t.Fatalf("response=%+v", resp)
	}
	if fake.path != "" {
		t.Fatal("executor should not be called")
	}
}

func TestRunnerRestartUsesNoShellAndNoBlock(t *testing.T) {
	runner, _ := NewRunner([]string{"control-center.service"}, []string{ActionSystemdStatus, ActionSystemdRestart})
	fake := &fakeExec{}
	runner.Exec = fake
	resp := runner.Execute(context.Background(), validRequest(ActionSystemdRestart, "control-center.service"))
	if resp.Status != "succeeded" {
		t.Fatalf("response=%+v", resp)
	}
	want := []string{"restart", "--no-block", "--", "control-center.service"}
	if strings.Join(fake.args, "\x00") != strings.Join(want, "\x00") {
		t.Fatalf("args=%q", fake.args)
	}
}

func TestRunnerMapsTimeout(t *testing.T) {
	runner, _ := NewRunner([]string{"control-center.service"}, []string{ActionSystemdStatus, ActionSystemdRestart})
	runner.Timeout = 5 * time.Millisecond
	fake := &fakeExec{block: true}
	runner.Exec = fake
	resp := runner.Execute(context.Background(), validRequest(ActionSystemdRestart, "control-center.service"))
	if resp.Error == nil || resp.Error.Code != "operation_timeout" {
		t.Fatalf("response=%+v", resp)
	}
}

func TestRunnerDoesNotExposeCommandError(t *testing.T) {
	runner, _ := NewRunner([]string{"control-center.service"}, []string{ActionSystemdStatus, ActionSystemdRestart})
	fake := &fakeExec{err: errors.New("secret stderr material")}
	runner.Exec = fake
	resp := runner.Execute(context.Background(), validRequest(ActionSystemdRestart, "control-center.service"))
	if resp.Error == nil || strings.Contains(resp.Error.Message, "secret") {
		t.Fatalf("response=%+v", resp)
	}
}

func TestRunnerRejectsActionNotEnabled(t *testing.T) {
	runner, err := NewRunner([]string{"control-center.service"}, []string{ActionSystemdStatus})
	if err != nil {
		t.Fatal(err)
	}
	fake := &fakeExec{}
	runner.Exec = fake
	resp := runner.Execute(context.Background(), validRequest(ActionSystemdRestart, "control-center.service"))
	if resp.Error == nil || resp.Error.Code != "action_not_allowed" {
		t.Fatalf("response=%+v", resp)
	}
	if fake.path != "" {
		t.Fatal("executor should not be called")
	}
}

func TestParseAllowedUnitsRejectsUnsafeValue(t *testing.T) {
	if _, err := ParseAllowedUnits("control-center.service,ssh.service;id.service"); err == nil {
		t.Fatal("expected rejection")
	}
}
