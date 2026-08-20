package httpserver

import (
	"crypto/rand"
	"embed"
	"encoding/hex"
	"encoding/json"
	"io/fs"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/ControlCenterSoft/srv-deployment/internal/buildinfo"
)

//go:embed web/*
var webFS embed.FS

type envelope map[string]any

func New(logger *slog.Logger) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v1/health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, envelope{
			"status":  "ok",
			"service": "control-center",
			"time":    time.Now().UTC().Format(time.RFC3339),
		})
	})
	mux.HandleFunc("GET /api/v1/readiness", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, envelope{
			"status": "ready",
			"ready":  true,
			"checks": []any{},
		})
	})
	mux.HandleFunc("GET /api/v1/version", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, envelope{
			"product":  "Control Center",
			"version":  buildinfo.Version,
			"commit":   buildinfo.Commit,
			"built_at": buildinfo.BuiltAt,
		})
	})
	mux.HandleFunc("/api/", func(w http.ResponseWriter, r *http.Request) {
		writeError(w, http.StatusNotFound, "api_not_found", "API endpoint not found", operationID(r))
	})

	static, err := fs.Sub(webFS, "web")
	if err != nil {
		panic(err)
	}
	mux.Handle("/", http.FileServer(http.FS(static)))

	return requestMiddleware(logger, mux)
}

func requestMiddleware(logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		opID := newOperationID()
		r.Header.Set("X-Control-Center-Operation-ID", opID)
		w.Header().Set("X-Control-Center-Operation-ID", opID)
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'")
		start := time.Now()
		next.ServeHTTP(w, r)
		logger.Info("http request", "method", r.Method, "path", r.URL.Path, "operation_id", opID, "duration_ms", time.Since(start).Milliseconds())
	})
}

func operationID(r *http.Request) string {
	if v := strings.TrimSpace(r.Header.Get("X-Control-Center-Operation-ID")); v != "" {
		return v
	}
	return "unknown"
}

func newOperationID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return time.Now().UTC().Format("20060102T150405.000000000")
	}
	return hex.EncodeToString(b[:])
}

func writeJSON(w http.ResponseWriter, status int, body envelope) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

func writeError(w http.ResponseWriter, status int, code, message, opID string) {
	writeJSON(w, status, envelope{
		"error": envelope{
			"code":         code,
			"message":      message,
			"operation_id": opID,
		},
	})
}
