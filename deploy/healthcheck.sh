#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
STATUS_FILE="/var/lib/srv-deployment/last-result.env"

fail() {
    printf 'HEALTHCHECK FAIL: %s\n' "$*" >&2
    exit 1
}

[[ "$(id -u)" -eq 0 ]] || fail "must run as root"
[[ -d "$PROJECT" ]] || fail "project directory missing: $PROJECT"
[[ -s "$STATUS_FILE" ]] || fail "deployment status file is missing"
systemctl is-active --quiet srv-control.service || fail "srv-control.service is not active"

grep -Fxq 'result=success' "$STATUS_FILE" || fail "last deployment result is not success"
if [[ "$REMOTE_SHA" != "unknown" ]]; then
    grep -Fxq "remote_sha=${REMOTE_SHA}" "$STATUS_FILE" || fail "status SHA does not match requested commit"
fi

printf 'HEALTHCHECK PASS: sha=%s\n' "$REMOTE_SHA"
