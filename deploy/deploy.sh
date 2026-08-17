#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
MARKER="${PROJECT}/DEPLOYMENT_STATUS.txt"

fail() {
    printf 'DEPLOY PROBE FAIL: %s\n' "$*" >&2
    exit 1
}

[[ "$(id -u)" -eq 0 ]] || fail "must run as root"
[[ -d "$PROJECT" ]] || fail "project directory missing: $PROJECT"
systemctl is-active --quiet srv-control.service || fail "srv-control.service is not active"

tmp="$(mktemp "${PROJECT}/.deployment-status.tmp.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
{
    printf 'result=success\n'
    printf 'stage=channel-probe\n'
    printf 'remote_sha=%s\n' "$REMOTE_SHA"
    printf 'applied_at=%s\n' "$(date -Is)"
    printf 'hostname=%s\n' "$(hostname -f 2>/dev/null || hostname)"
} > "$tmp"
chmod 0644 "$tmp"
mv -f "$tmp" "$MARKER"
trap - EXIT

printf 'DEPLOY PROBE PASS: sha=%s\n' "$REMOTE_SHA"
