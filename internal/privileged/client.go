package privileged

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"time"
)

type Client struct {
	SocketPath string
	Timeout    time.Duration
}

func (c Client) Do(ctx context.Context, req Request) (Response, error) {
	timeout := c.Timeout
	if timeout <= 0 || timeout > 30*time.Second {
		timeout = 5 * time.Second
	}
	dialer := net.Dialer{Timeout: timeout}
	conn, err := dialer.DialContext(ctx, "unix", c.SocketPath)
	if err != nil {
		return Response{}, err
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(timeout))
	if err := json.NewEncoder(conn).Encode(req); err != nil {
		return Response{}, err
	}
	var resp Response
	dec := json.NewDecoder(conn)
	dec.DisallowUnknownFields()
	if err := dec.Decode(&resp); err != nil {
		return Response{}, err
	}
	if resp.Schema != SchemaVersion || resp.OperationID != req.OperationID {
		return Response{}, errors.New("privileged response identity mismatch")
	}
	return resp, nil
}
