package privileged

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"os"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const maxRequestBytes = 16 << 10

type Server struct {
	SocketPath  string
	SocketGroup string
	AllowedUID  int
	Runner      *Runner
	Logger      *slog.Logger
}

func (s *Server) Serve(ctx context.Context) error {
	if s.Runner == nil {
		return errors.New("runner is required")
	}
	if s.AllowedUID < 0 {
		return errors.New("allowed client uid is required")
	}
	if s.SocketPath == "" || !filepath.IsAbs(s.SocketPath) {
		return errors.New("absolute socket path is required")
	}
	if s.Logger == nil {
		s.Logger = slog.Default()
	}
	if err := os.MkdirAll(filepath.Dir(s.SocketPath), 0o750); err != nil {
		return fmt.Errorf("create socket directory: %w", err)
	}
	if err := removeStaleSocket(s.SocketPath); err != nil {
		return err
	}
	ln, err := net.Listen("unix", s.SocketPath)
	if err != nil {
		return fmt.Errorf("listen unix socket: %w", err)
	}
	defer func() {
		_ = ln.Close()
		_ = os.Remove(s.SocketPath)
	}()
	if err := os.Chmod(s.SocketPath, 0o660); err != nil {
		return fmt.Errorf("chmod unix socket: %w", err)
	}
	if s.SocketGroup != "" {
		group, err := user.LookupGroup(s.SocketGroup)
		if err != nil {
			return fmt.Errorf("lookup socket group: %w", err)
		}
		gid, err := strconv.Atoi(group.Gid)
		if err != nil {
			return fmt.Errorf("parse socket group: %w", err)
		}
		if err := os.Chown(s.SocketPath, 0, gid); err != nil {
			return fmt.Errorf("chown unix socket: %w", err)
		}
	}

	go func() {
		<-ctx.Done()
		_ = ln.Close()
	}()
	for {
		conn, err := ln.Accept()
		if err != nil {
			if ctx.Err() != nil || errors.Is(err, net.ErrClosed) {
				return nil
			}
			return fmt.Errorf("accept unix socket: %w", err)
		}
		go s.handle(ctx, conn)
	}
}

func (s *Server) handle(parent context.Context, conn net.Conn) {
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(10 * time.Second))
	uid, err := peerUID(conn)
	if err != nil || uid != s.AllowedUID {
		s.Logger.Warn("privileged peer rejected", "peer_uid", uid, "error", err)
		return
	}
	limited := io.LimitReader(conn, maxRequestBytes+1)
	dec := json.NewDecoder(bufio.NewReader(limited))
	dec.DisallowUnknownFields()
	var req Request
	if err := dec.Decode(&req); err != nil {
		s.writeResponse(conn, Response{Schema: SchemaVersion, OperationID: req.OperationID, Status: "rejected", Error: &Error{Code: "invalid_json", Message: "invalid request"}})
		return
	}
	var extra any
	if err := dec.Decode(&extra); !errors.Is(err, io.EOF) {
		s.writeResponse(conn, Response{Schema: SchemaVersion, OperationID: req.OperationID, Status: "rejected", Error: &Error{Code: "invalid_json", Message: "request must contain one JSON object"}})
		return
	}
	started := time.Now()
	resp := s.Runner.Execute(parent, req)
	s.Logger.Info("privileged operation", "operation_id", req.OperationID, "action", req.Action, "target", req.Target, "status", resp.Status, "error_code", errorCode(resp), "duration_ms", time.Since(started).Milliseconds())
	s.writeResponse(conn, resp)
}

func (s *Server) writeResponse(conn net.Conn, resp Response) {
	_ = json.NewEncoder(conn).Encode(resp)
}

func errorCode(resp Response) string {
	if resp.Error == nil {
		return ""
	}
	return resp.Error.Code
}

func removeStaleSocket(path string) error {
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("inspect unix socket: %w", err)
	}
	if info.Mode()&os.ModeSocket == 0 {
		return errors.New("refusing to replace non-socket path")
	}
	return os.Remove(path)
}

func ParseAllowedUnits(raw string) ([]string, error) {
	parts := strings.Split(raw, ",")
	units := make([]string, 0, len(parts))
	seen := map[string]struct{}{}
	for _, part := range parts {
		unit := strings.TrimSpace(part)
		if unit == "" {
			continue
		}
		req := Request{Schema: SchemaVersion, OperationID: strings.Repeat("a", 32), Action: ActionSystemdStatus, Target: unit}
		if err := req.Validate(); err != nil {
			return nil, fmt.Errorf("invalid allowed unit %q: %w", unit, err)
		}
		if _, ok := seen[unit]; ok {
			continue
		}
		seen[unit] = struct{}{}
		units = append(units, unit)
	}
	if len(units) == 0 {
		return nil, errors.New("no allowed units configured")
	}
	return units, nil
}
