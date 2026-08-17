#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
MARKER="${PROJECT}/DEPLOYMENT_STATUS.txt"

fail() {
    printf 'HEALTHCHECK FAIL: %s\n' "$*" >&2
    exit 1
}

[[ -s "$MARKER" ]] || fail "deployment marker is missing"
systemctl is-active --quiet srv-control.service || fail "srv-control.service is not active"
grep -Fxq 'result=success' "$MARKER" || fail "deployment marker is not successful"
grep -Fxq 'stage=channel-probe' "$MARKER" || fail "unexpected deployment stage"
if [[ "$REMOTE_SHA" != "unknown" ]]; then
    grep -Fxq "remote_sha=${REMOTE_SHA}" "$MARKER" || fail "deployment marker SHA mismatch"
fi

printf 'HEALTHCHECK PASS: sha=%s\n' "$REMOTE_SHA"
