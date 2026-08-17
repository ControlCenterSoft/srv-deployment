#!/usr/bin/env bash
set -Eeuo pipefail

RELEASE_ID="0001-channel-acceptance"
STATE_ROOT="/var/lib/srv-deployment"
MARKER_DIR="${STATE_ROOT}/release-markers"
PROJECT="/opt/srv-control"

fail() {
    printf 'PRECHECK FAIL: %s\n' "$*" >&2
    exit 1
}

[[ "$(id -u)" -eq 0 ]] || fail "must run as root"
[[ -d "$PROJECT" ]] || fail "project directory missing: $PROJECT"
command -v systemctl >/dev/null 2>&1 || fail "systemctl unavailable"
systemctl is-active --quiet srv-control.service || fail "srv-control.service is not active"

install -d -m 0750 "$MARKER_DIR"

printf 'PRECHECK PASS: %s\n' "$RELEASE_ID"
