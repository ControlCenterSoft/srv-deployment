package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"runtime"
	"syscall"
	"time"

	"github.com/ControlCenterSoft/srv-deployment/internal/buildinfo"
	"github.com/ControlCenterSoft/srv-deployment/internal/httpserver"
	"github.com/ControlCenterSoft/srv-deployment/internal/observability"
	"github.com/ControlCenterSoft/srv-deployment/internal/operations"
	"github.com/ControlCenterSoft/srv-deployment/internal/release"
	"github.com/ControlCenterSoft/srv-deployment/internal/state"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	stateDir := envOr("CONTROL_CENTER_STATE_DIR", "/var/lib/control-center")
	logDir := envOr("CONTROL_CENTER_LOG_DIR", "/var/log/control-center")

	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "bootstrap-admin":
			bootstrapAdmin(logger, stateDir, os.Args[2:])
			return
		case "build-info":
			buildInfo(os.Args[2:])
			return
		case "verify-release":
			verifyRelease(os.Args[2:])
			return
		case "compare-version":
			compareVersion(os.Args[2:])
			return
		case "privileged-worker":
			privilegedWorker(logger, os.Args[2:])
			return
		case "privileged-call":
			privilegedCall(os.Args[2:])
			return
		}
	}

	store, err := state.Open(stateDir)
	if err != nil {
		logger.Error("state initialization failed", "error", err)
		os.Exit(1)
	}
	opStore, err := operations.Open(stateDir)
	if err != nil {
		logger.Error("operation store initialization failed", "error", err)
		os.Exit(1)
	}
	audit, err := observability.OpenAudit(logDir)
	if err != nil {
		logger.Error("audit initialization failed", "error", err)
		os.Exit(1)
	}

	listen := envOr("CONTROL_CENTER_LISTEN", "127.0.0.1:8876")
	srv := &http.Server{Addr: listen, Handler: httpserver.New(logger, store, opStore, audit), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 15 * time.Second, WriteTimeout: 30 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 1 << 20}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	errCh := make(chan error, 1)
	go func() {
		logger.Info("control center starting", "listen", listen, "state_dir", stateDir, "log_dir", logDir)
		errCh <- srv.ListenAndServe()
	}()
	select {
	case <-ctx.Done():
		logger.Info("shutdown requested")
	case err := <-errCh:
		if !errors.Is(err, http.ErrServerClosed) {
			logger.Error("http server failed", "error", err)
			os.Exit(1)
		}
		return
	}
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		logger.Error("graceful shutdown failed", "error", err)
		os.Exit(1)
	}
	logger.Info("control center stopped")
}

func buildInfo(args []string) {
	fs := flag.NewFlagSet("build-info", flag.ExitOnError)
	field := fs.String("field", "", "version|commit|built-at")
	_ = fs.Parse(args)
	switch *field {
	case "version":
		fmt.Println(buildinfo.Version)
	case "commit":
		fmt.Println(buildinfo.Commit)
	case "built-at":
		fmt.Println(buildinfo.BuiltAt)
	case "":
		fmt.Printf("{\"version\":%q,\"commit\":%q,\"built_at\":%q}\n", buildinfo.Version, buildinfo.Commit, buildinfo.BuiltAt)
	default:
		fmt.Fprintln(os.Stderr, "unknown build-info field")
		os.Exit(2)
	}
}

func verifyRelease(args []string) {
	fs := flag.NewFlagSet("verify-release", flag.ExitOnError)
	manifest := fs.String("manifest", "", "manifest path")
	signature := fs.String("signature", "", "signature path")
	publicKey := fs.String("public-key", "", "trusted Ed25519 public key")
	artifact := fs.String("artifact", "", "candidate binary")
	field := fs.String("field", "release-id", "release-id|version|commit")
	_ = fs.Parse(args)
	if *manifest == "" || *signature == "" || *publicKey == "" || *artifact == "" {
		fs.Usage()
		os.Exit(2)
	}
	m, err := release.Verify(*manifest, *signature, *publicKey, *artifact, runtime.GOOS, runtime.GOARCH, state.SchemaVersion)
	if err != nil {
		fmt.Fprintln(os.Stderr, "release verification failed:", err)
		os.Exit(1)
	}
	switch *field {
	case "release-id":
		fmt.Println(m.ReleaseID())
	case "version":
		fmt.Println(m.Version)
	case "commit":
		fmt.Println(m.Commit)
	default:
		fmt.Fprintln(os.Stderr, "unknown verify-release field")
		os.Exit(2)
	}
}

func compareVersion(args []string) {
	fs := flag.NewFlagSet("compare-version", flag.ExitOnError)
	current := fs.String("current", buildinfo.Version, "current version")
	target := fs.String("target", "", "target version")
	_ = fs.Parse(args)
	if *target == "" {
		fs.Usage()
		os.Exit(2)
	}
	cmp, err := release.CompareVersions(*current, *target)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Println(cmp)
}

func bootstrapAdmin(logger *slog.Logger, stateDir string, args []string) {
	fs := flag.NewFlagSet("bootstrap-admin", flag.ExitOnError)
	username := fs.String("username", "admin", "initial administrator username")
	_ = fs.Parse(args)
	store, err := state.Open(stateDir)
	if err != nil {
		logger.Error("state initialization failed", "error", err)
		os.Exit(1)
	}
	_, created, err := store.BootstrapAdmin(*username)
	if err != nil {
		logger.Error("admin bootstrap failed", "error", err)
		os.Exit(1)
	}
	if created {
		fmt.Printf("Initial administrator created. Bootstrap credentials: %s\n", filepath.Join(stateDir, "bootstrap-admin.secret"))
		return
	}
	fmt.Println("Administrator bootstrap skipped: state already contains users.")
}

func envOr(name, fallback string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return fallback
}
