package privileged

import (
	"context"
	"errors"
	"os/exec"
)

type ExecRunner struct{}

func (ExecRunner) Run(ctx context.Context, executable string, args ...string) (CommandResult, error) {
	cmd := exec.CommandContext(ctx, executable, args...)
	output, err := cmd.CombinedOutput()

	result := CommandResult{
		ExitCode: 0,
		Output:   string(output),
	}
	if err == nil {
		return result, nil
	}

	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		result.ExitCode = exitErr.ExitCode()
	} else {
		result.ExitCode = -1
	}
	if ctx.Err() != nil {
		return result, ctx.Err()
	}
	return result, err
}
