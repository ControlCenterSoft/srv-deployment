#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE="${1:-srv-control.service}"
HEALTH_URL="${2:-http://127.0.0.1:8876/api/v1/health}"

log() {
    printf '%s %s\n' "$(date -Is)" "$*"
}

wait_health() {
    python3 - "$HEALTH_URL" <<'PY'
import json
import sys
import time
import urllib.request

url = sys.argv[1]
last_error = None

for _ in range(30):
    try:
        with urllib.request.urlopen(url, timeout=3) as response:
            payload = json.load(response)

        if payload.get("ok") is True:
            raise SystemExit(0)

        last_error = f"unexpected payload: {payload!r}"

    except Exception as exc:
        last_error = repr(exc)

    time.sleep(1)

raise SystemExit(f"health did not recover: {last_error}")
PY
}

if ! systemctl is-active --quiet "$SERVICE"; then
    log "RELOAD: service is not active; starting"
    systemctl start "$SERVICE"
    wait_health
    log "RELOAD PASS: service started"
    exit 0
fi

exec_start="$(systemctl show "$SERVICE" -p ExecStart --value 2>/dev/null || true)"

if [[ "$exec_start" == *"--workers 2"* ]]; then
    log "RELOAD: sending SIGHUP to Uvicorn manager for graceful worker rotation"
    systemctl kill --kill-who=main --signal=HUP "$SERVICE"
    wait_health
    log "RELOAD PASS: workers rotated without stopping listener"
    exit 0
fi

log "RELOAD: legacy single-process service detected; using one-time restart"
systemctl restart "$SERVICE"
wait_health
log "RELOAD PASS: legacy service restarted"
