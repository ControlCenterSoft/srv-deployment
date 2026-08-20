//go:build linux

package privileged

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"slices"
	"syscall"
	"time"
)

const defaultMaxRequestBytes int64 = 16 * 1024

type SocketServer struct {
	Engine          *Engine
	AllowedUIDs     []uint32
	MaxRequestBytes int64
	Audit           AuditSink
}

func NewSocketServer(engine *Engine, allowedUIDs []uint32) (*SocketServer, error) {
	if engine == nil {
		return nil, fmt.Errorf("%w: engine is required", ErrInvalidRequest)
	}
	if len(allowedUIDs) == 0 {
		return nil, fmt.Errorf("%w: allowed uid list is empty", ErrInvalidRequest)
	}

	uids := append([]uint32(nil), allowedUIDs...)
	slices.Sort(uids)
	uids = slices.Compact(uids)

	return &SocketServer{
		Engine:          engine,
		AllowedUIDs:     uids,
		MaxRequestBytes: defaultMaxRequestBytes,
	}, nil
}

func (s *SocketServer) Serve(ctx context.Context, listener *net.UnixListener) error {
	if listener == nil {
		return fmt.Errorf("%w: listener is required", ErrInvalidRequest)
	}
	defer listener.Close()

	for {
		if err := listener.SetDeadline(time.Now().Add(500 * time.Millisecond)); err != nil {
			return err
		}
		conn, err := listener.AcceptUnix()
		if err != nil {
			if errors.Is(ctx.Err(), context.Canceled) || errors.Is(ctx.Err(), context.DeadlineExceeded) {
				return ctx.Err()
			}
			if ne, ok := err.(net.Error); ok && ne.Timeout() {
				continue
			}
			return err
		}
		go func() {
			defer conn.Close()
			_ = s.HandleConn(ctx, conn)
		}()
	}
}

func (s *SocketServer) HandleConn(ctx context.Context, conn *net.UnixConn) error {
	if conn == nil {
		return fmt.Errorf("%w: unix connection is required", ErrInvalidRequest)
	}

	uid, err := peerUID(conn)
	if err != nil {
		return s.writeFailure(conn, Result{Status: "failed", ExitCode: -1}, ErrorCodeProtocol, "peer credentials unavailable")
	}
	if !slices.Contains(s.AllowedUIDs, uid) {
		return s.writeFailure(conn, Result{Status: "failed", ExitCode: -1}, ErrorCodePermissionDenied, "peer uid is not authorized")
	}

	maxBytes := s.MaxRequestBytes
	if maxBytes <= 0 || maxBytes > 1024*1024 {
		maxBytes = defaultMaxRequestBytes
	}

	limited := io.LimitReader(conn, maxBytes+1)
	payload, err := io.ReadAll(limited)
	if err != nil {
		return s.writeFailure(conn, Result{Status: "failed", ExitCode: -1}, ErrorCodeProtocol, "request read failed")
	}
	if int64(len(payload)) > maxBytes {
		return s.writeFailure(conn, Result{Status: "failed", ExitCode: -1}, ErrorCodeProtocol, "request exceeds size limit")
	}

	var envelope Envelope
	decoder := json.NewDecoder(bufio.NewReaderSize(bytesReader(payload), len(payload)+1))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&envelope); err != nil {
		return s.writeFailure(conn, Result{Status: "failed", ExitCode: -1}, ErrorCodeProtocol, "invalid request envelope")
	}
	if decoder.Decode(&struct{}{}) != io.EOF {
		return s.writeFailure(conn, Result{ID: envelope.Request.ID, Type: envelope.Request.Type, Status: "failed", ExitCode: -1}, ErrorCodeProtocol, "multiple request values are forbidden")
	}
	if envelope.Version != ProtocolVersion {
		return s.writeFailure(conn, Result{ID: envelope.Request.ID, Type: envelope.Request.Type, Status: "failed", ExitCode: -1}, ErrorCodeProtocol, "unsupported protocol version")
	}

	startedAt := time.Now().UTC()
	result, execErr := s.Engine.Execute(ctx, envelope.Request)
	finishedAt := time.Now().UTC()
	failure := failureFor(execErr)
	s.recordAudit(envelope.Request, result, failure, startedAt, finishedAt)

	response := ResponseEnvelope{Version: ProtocolVersion, Result: result, Error: failure}
	return json.NewEncoder(conn).Encode(response)
}

func (s *SocketServer) recordAudit(req Request, result Result, failure *Failure, startedAt, finishedAt time.Time) {
	if s.Audit == nil {
		return
	}
	errorCode := ""
	if failure != nil {
		errorCode = failure.Code
	}
	status := result.Status
	if status == "" {
		status = "failed"
	}
	duration := finishedAt.Sub(startedAt)
	if duration < 0 {
		duration = 0
	}
	s.Audit.Record(AuditEvent{
		OperationID: req.ID,
		ActorID:     req.ActorID,
		Type:        req.Type,
		Status:      status,
		ExitCode:    result.ExitCode,
		ErrorCode:   errorCode,
		StartedAt:   startedAt,
		FinishedAt:  finishedAt,
		DurationMS:  duration.Milliseconds(),
	})
}

func (s *SocketServer) writeFailure(conn *net.UnixConn, result Result, code, message string) error {
	return json.NewEncoder(conn).Encode(ResponseEnvelope{
		Version: ProtocolVersion,
		Result:  result,
		Error:   &Failure{Code: code, Message: message},
	})
}

func peerUID(conn *net.UnixConn) (uint32, error) {
	raw, err := conn.SyscallConn()
	if err != nil {
		return 0, err
	}

	var (
		uid      uint32
		innerErr error
	)
	if err := raw.Control(func(fd uintptr) {
		cred, err := syscall.GetsockoptUcred(int(fd), syscall.SOL_SOCKET, syscall.SO_PEERCRED)
		if err != nil {
			innerErr = err
			return
		}
		uid = cred.Uid
	}); err != nil {
		return 0, err
	}
	if innerErr != nil {
		return 0, innerErr
	}
	return uid, nil
}

func ListenUnix(path string, mode os.FileMode) (*net.UnixListener, error) {
	if path == "" {
		return nil, fmt.Errorf("%w: socket path is required", ErrInvalidRequest)
	}
	if mode&0600 != 0600 || mode&0007 != 0 {
		return nil, fmt.Errorf("%w: socket mode must grant owner rw and deny world access", ErrInvalidRequest)
	}
	_ = os.Remove(path)
	listener, err := net.ListenUnix("unix", &net.UnixAddr{Name: path, Net: "unix"})
	if err != nil {
		return nil, err
	}
	if err := os.Chmod(path, mode); err != nil {
		listener.Close()
		_ = os.Remove(path)
		return nil, err
	}
	return listener, nil
}

// bytesReader avoids accepting a streaming sequence of JSON documents while keeping a bounded payload.
type staticReader struct {
	payload []byte
	offset  int
}

func bytesReader(payload []byte) *staticReader {
	return &staticReader{payload: payload}
}

func (r *staticReader) Read(p []byte) (int, error) {
	if r.offset >= len(r.payload) {
		return 0, io.EOF
	}
	n := copy(p, r.payload[r.offset:])
	r.offset += n
	return n, nil
}
