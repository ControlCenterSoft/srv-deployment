//go:build linux

package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"os/user"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/ControlCenterSoft/srv-deployment/internal/privileged"
)

const (
	defaultSocketPath = "/run/control-center/privileged-worker.sock"
	defaultAuditPath  = "/var/log/control-center-privileged/audit.jsonl"
)

func main() {
	if err := run(); err != nil {
		log.Printf("privileged worker failed: %v", err)
		os.Exit(1)
	}
}

func run() error {
	allowedUser := envOr("CONTROL_CENTER_ALLOWED_USER", "control-center")
	account, err := user.Lookup(allowedUser)
	if err != nil {
		return fmt.Errorf("lookup allowed user %q: %w", allowedUser, err)
	}
	uid64, err := strconv.ParseUint(account.Uid, 10, 32)
	if err != nil {
		return fmt.Errorf("parse uid for %q: %w", allowedUser, err)
	}
	gid, err := strconv.Atoi(account.Gid)
	if err != nil || gid < 0 {
		return fmt.Errorf("parse gid for %q", allowedUser)
	}

	services := splitCSV(envOr("CONTROL_CENTER_ALLOWED_SERVICES", "control-center.service"))
	engine, err := privileged.NewEngine(privileged.ExecRunner{}, services, 10*time.Second)
	if err != nil {
		return err
	}

	audit, err := privileged.NewJSONLAuditSink(envOr("CONTROL_CENTER_PRIVILEGED_AUDIT", defaultAuditPath))
	if err != nil {
		return err
	}
	if err := audit.Ready(); err != nil {
		return fmt.Errorf("durable audit preflight: %w", err)
	}

	server, err := privileged.NewSocketServer(engine, []uint32{uint32(uid64)})
	if err != nil {
		return err
	}
	server.DurableAudit = audit

	socketPath := envOr("CONTROL_CENTER_PRIVILEGED_SOCKET", defaultSocketPath)
	listener, err := privileged.ListenUnix(socketPath, 0660)
	if err != nil {
		return err
	}
	defer os.Remove(socketPath)

	info, err := os.Stat(socketPath)
	if err != nil {
		listener.Close()
		return fmt.Errorf("stat socket ownership: %w", err)
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok {
		listener.Close()
		return fmt.Errorf("inspect socket ownership")
	}
	if stat.Uid != 0 || int(stat.Gid) != gid {
		if err := os.Chown(socketPath, 0, gid); err != nil {
			listener.Close()
			return fmt.Errorf("set socket ownership: %w", err)
		}
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	log.Printf("privileged worker ready: socket=%s allowed_user=%s uid=%d", socketPath, allowedUser, uid64)
	if err := server.Serve(ctx, listener); err != nil && ctx.Err() == nil {
		return err
	}
	return nil
}

func envOr(name, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	return fallback
}

func splitCSV(value string) []string {
	parts := strings.Split(value, ",")
	out := make([]string, 0, len(parts))
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part != "" {
			out = append(out, part)
		}
	}
	return out
}
