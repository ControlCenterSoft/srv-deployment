#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_COMMIT="d1ef2551c829e9b4b34d83bbdc2ec46baa8c9eca"
EXPECTED_VERSION="1.0.0-beta.1"
BACKEND_URL="http://127.0.0.1:8877"
PROXY_URL="http://127.0.0.1:8876"
CURRENT="/usr/local/lib/control-center/current"
BIN="$CURRENT/control-center"
ENV_FILE="/etc/control-center/control-center.env"
WORK="/opt/control-center-beta1-repair-recovery"
REPORT="$WORK/report.txt"

[[ $EUID -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
mkdir -p "$WORK"; chmod 0700 "$WORK"

wait_ready() {
  for _ in {1..60}; do
    if curl -fsS --max-time 2 "$BACKEND_URL/api/v1/readiness" 2>/dev/null | grep -Fq '"ready":true'; then return 0; fi
    sleep 0.25
  done
  return 1
}

snapshot() {
  {
    echo "CONTROL CENTER BETA1 POST-REPAIR DIAGNOSTIC"
    echo "time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "service_active=$(systemctl is-active control-center.service 2>/dev/null || true)"
    echo "service_failed=$(systemctl is-failed control-center.service 2>/dev/null || true)"
    echo "service_result=$(systemctl show control-center.service -p Result --value 2>/dev/null || true)"
    echo "service_restarts=$(systemctl show control-center.service -p NRestarts --value 2>/dev/null || true)"
    echo "current_target=$(readlink "$CURRENT" 2>/dev/null || true)"
    echo "current_version=$([[ -x "$BIN" ]] && "$BIN" build-info --field version 2>/dev/null || true)"
    echo "current_commit=$([[ -x "$BIN" ]] && "$BIN" build-info --field commit 2>/dev/null || true)"
    echo "listen_config=$(grep '^CONTROL_CENTER_LISTEN=' "$ENV_FILE" 2>/dev/null || true)"
    echo "port_8877=$(ss -ltnp 2>/dev/null | grep ':8877 ' || true)"
    echo "port_8876=$(ss -ltnp 2>/dev/null | grep ':8876 ' || true)"
    echo
    echo "--- SYSTEMD STATUS ---"
    systemctl status control-center.service --no-pager -l 2>&1 | tail -n 100 || true
    echo
    echo "--- JOURNAL TAIL ---"
    journalctl -u control-center.service --no-pager -n 180 2>&1 || true
    echo
    echo "NOTE: no passwords, cookies, CSRF tokens or request bodies are included."
  } > "$REPORT"
  chmod 0600 "$REPORT"
}

snapshot

[[ -L "$CURRENT" && -x "$BIN" ]] || { echo "RECOVERY=FAILED"; echo "REASON=current-runtime-missing"; echo "REPORT=$REPORT"; exit 1; }
version="$($BIN build-info --field version 2>/dev/null || true)"
commit="$($BIN build-info --field commit 2>/dev/null || true)"
[[ "$version" == "$EXPECTED_VERSION" && "$commit" == "$EXPECTED_COMMIT" ]] || {
  echo "RECOVERY=FAILED"
  echo "REASON=current-runtime-not-exact-beta1"
  echo "CURRENT_VERSION=$version"
  echo "CURRENT_COMMIT=$commit"
  echo "REPORT=$REPORT"
  exit 1
}

grep -qx 'CONTROL_CENTER_LISTEN=127.0.0.1:8877' "$ENV_FILE" || {
  echo "RECOVERY=FAILED"
  echo "REASON=unexpected-listen-config"
  echo "REPORT=$REPORT"
  exit 1
}

if grep -Eqi 'start request repeated too quickly|start-limit-hit' "$REPORT"; then
  reason="start-limit-hit"
else
  reason="service-restart-failure"
fi

systemctl reset-failed control-center.service
systemctl daemon-reload
systemctl start control-center.service
wait_ready

backend_version="$(curl -fsS "$BACKEND_URL/api/v1/version")"
proxy_health="$(curl -fsS "$PROXY_URL/api/v1/health" 2>/dev/null || true)"

snapshot

echo "RECOVERY=PASSED"
echo "RECOVERY_REASON=$reason"
echo "SERVICE_ACTIVE=$(systemctl is-active control-center.service)"
echo "BACKEND_READY=true"
echo "VERSION=$backend_version"
if [[ -n "$proxy_health" ]]; then echo "PROXY_HEALTH=$proxy_health"; else echo "PROXY_HEALTH=unavailable"; fi
echo "REPORT=$REPORT"
