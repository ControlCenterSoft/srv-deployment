//go:build linux

package privileged

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"time"
)

type SocketClient struct {
	Path    string
	Timeout time.Duration
}

func (c SocketClient) Execute(ctx context.Context, req Request) (Result, error) {
	result := Result{ID: req.ID, Type: req.Type, Status: "failed", ExitCode: -1}
	if c.Path == "" {
		return result, fmt.Errorf("%w: socket path is required", ErrInvalidRequest)
	}
	timeout := c.Timeout
	if timeout <= 0 || timeout > 35*time.Second {
		timeout = 35 * time.Second
	}

	dialer := net.Dialer{Timeout: timeout}
	connRaw, err := dialer.DialContext(ctx, "unix", c.Path)
	if err != nil {
		return result, fmt.Errorf("dial privileged worker: %w", err)
	}
	conn := connRaw.(*net.UnixConn)
	defer conn.Close()

	deadline := time.Now().Add(timeout)
	if ctxDeadline, ok := ctx.Deadline(); ok && ctxDeadline.Before(deadline) {
		deadline = ctxDeadline
	}
	if err := conn.SetDeadline(deadline); err != nil {
		return result, err
	}

	if err := json.NewEncoder(conn).Encode(Envelope{Version: ProtocolVersion, Request: req}); err != nil {
		return result, fmt.Errorf("write privileged request: %w", err)
	}
	if err := conn.CloseWrite(); err != nil {
		return result, fmt.Errorf("finish privileged request: %w", err)
	}

	var response ResponseEnvelope
	decoder := json.NewDecoder(conn)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&response); err != nil {
		if errors.Is(ctx.Err(), context.DeadlineExceeded) {
			return result, ctx.Err()
		}
		return result, fmt.Errorf("read privileged response: %w", err)
	}
	if response.Version != ProtocolVersion {
		return result, &RemoteError{Code: ErrorCodeProtocol, Message: "unsupported response protocol version"}
	}
	if response.Result.ID != req.ID || response.Result.Type != req.Type {
		return result, &RemoteError{Code: ErrorCodeProtocol, Message: "response identity mismatch"}
	}
	if response.Error != nil {
		return response.Result, &RemoteError{Code: response.Error.Code, Message: response.Error.Message}
	}
	return response.Result, nil
}
