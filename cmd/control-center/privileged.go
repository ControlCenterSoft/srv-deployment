package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"os/user"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/ControlCenterSoft/srv-deployment/internal/privileged"
)

func privilegedWorker(logger *slog.Logger, args []string) {
	fs := flag.NewFlagSet("privileged-worker", flag.ExitOnError)
	socketPath := fs.String("socket", envOr("CONTROL_CENTER_PRIVILEGED_SOCKET", "/run/control-center-privileged/worker.sock"), "Unix socket path")
	clientUser := fs.String("client-user", envOr("CONTROL_CENTER_PRIVILEGED_CLIENT_USER", "control-center"), "allowed client user")
	socketGroup := fs.String("socket-group", envOr("CONTROL_CENTER_PRIVILEGED_SOCKET_GROUP", "control-center"), "Unix socket group")
	unitsRaw := fs.String("units", envOr("CONTROL_CENTER_PRIVILEGED_UNITS", "control-center.service"), "comma-separated allowlisted systemd units")
	actionsRaw := fs.String("actions", envOr("CONTROL_CENTER_PRIVILEGED_ACTIONS", privileged.ActionSystemdStatus), "comma-separated allowlisted privileged actions")
	_ = fs.Parse(args)
	if fs.NArg() != 0 {
		fs.Usage()
		os.Exit(2)
	}

	units, err := privileged.ParseAllowedUnits(*unitsRaw)
	if err != nil {
		logger.Error("privileged unit policy invalid", "error", err)
		os.Exit(1)
	}
	actions, err := privileged.ParseAllowedActions(*actionsRaw)
	if err != nil {
		logger.Error("privileged action policy invalid", "error", err)
		os.Exit(1)
	}
	account, err := user.Lookup(*clientUser)
	if err != nil {
		logger.Error("privileged client user lookup failed", "user", *clientUser, "error", err)
		os.Exit(1)
	}
	uid, err := strconv.Atoi(account.Uid)
	if err != nil || uid <= 0 {
		logger.Error("privileged client uid invalid", "user", *clientUser, "uid", account.Uid)
		os.Exit(1)
	}
	runner, err := privileged.NewRunner(units, actions)
	if err != nil {
		logger.Error("privileged runner initialization failed", "error", err)
		os.Exit(1)
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	server := &privileged.Server{SocketPath: *socketPath, SocketGroup: *socketGroup, AllowedUID: uid, Runner: runner, Logger: logger}
	logger.Info("privileged worker starting", "socket", *socketPath, "client_user", *clientUser, "units", units, "actions", actions)
	if err := server.Serve(ctx); err != nil {
		logger.Error("privileged worker failed", "error", err)
		os.Exit(1)
	}
	logger.Info("privileged worker stopped")
}

func privilegedCall(args []string) {
	fs := flag.NewFlagSet("privileged-call", flag.ExitOnError)
	socketPath := fs.String("socket", envOr("CONTROL_CENTER_PRIVILEGED_SOCKET", "/run/control-center-privileged/worker.sock"), "Unix socket path")
	action := fs.String("action", "", "typed privileged action")
	target := fs.String("target", "", "allowlisted target")
	opID := fs.String("operation-id", strings.Repeat("a", 32), "32-character lowercase hexadecimal operation id")
	timeout := fs.Duration("timeout", 5*time.Second, "request timeout")
	_ = fs.Parse(args)
	if fs.NArg() != 0 || *action == "" || *target == "" {
		fs.Usage()
		os.Exit(2)
	}
	req := privileged.Request{Schema: privileged.SchemaVersion, OperationID: *opID, Action: *action, Target: *target}
	if err := req.Validate(); err != nil {
		fmt.Fprintln(os.Stderr, "invalid privileged request:", err)
		os.Exit(2)
	}
	ctx, cancel := context.WithTimeout(context.Background(), *timeout)
	defer cancel()
	resp, err := (privileged.Client{SocketPath: *socketPath, Timeout: *timeout}).Do(ctx, req)
	if err != nil {
		fmt.Fprintln(os.Stderr, "privileged request failed:", err)
		os.Exit(1)
	}
	_ = json.NewEncoder(os.Stdout).Encode(resp)
	if resp.Status != "succeeded" {
		os.Exit(1)
	}
}
