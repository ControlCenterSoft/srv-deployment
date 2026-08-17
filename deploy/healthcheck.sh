#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
STATUS_FILE="/var/lib/srv-deployment/last-result.env"
STATE_REPO="/var/lib/srvcc-agent/state-repo"
ACK_FILE="${STATE_REPO}/deployment-status.env"

fail() {
    printf 'HEALTHCHECK FAIL: %s\n' "$*" >&2
    exit 1
}

[[ "$(id -u)" -eq 0 ]] || fail "must run as root"
[[ -d "$PROJECT" ]] || fail "project directory missing: $PROJECT"
[[ -s "$STATUS_FILE" ]] || fail "deployment status file is missing"
command -v git >/dev/null 2>&1 || fail "git is required"
systemctl is-active --quiet srv-control.service || fail "srv-control.service is not active"

grep -Fxq 'result=success' "$STATUS_FILE" || fail "last deployment result is not success"
if [[ "$REMOTE_SHA" != "unknown" ]]; then
    grep -Fxq "remote_sha=${REMOTE_SHA}" "$STATUS_FILE" || fail "status SHA does not match requested commit"
fi

[[ -d "${STATE_REPO}/.git" ]] || fail "server-state repository is missing: ${STATE_REPO}"

cd "$STATE_REPO"
git fetch origin server-state >/dev/null 2>&1 || fail "cannot fetch server-state"
git reset --hard origin/server-state >/dev/null || fail "cannot reset server-state worktree"

tmp="$(mktemp "${ACK_FILE}.tmp.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
cat "$STATUS_FILE" > "$tmp"
printf 'acknowledged_at=%s\n' "$(date -Is)" >> "$tmp"
printf 'hostname=%s\n' "$(hostname -f 2>/dev/null || hostname)" >> "$tmp"
chmod 0644 "$tmp"
mv -f "$tmp" "$ACK_FILE"
trap - EXIT

git add -- deployment-status.env
if ! git diff --cached --quiet; then
    git -c user.name='SRV Deployment' \
        -c user.email='srv-deployment@localhost' \
        commit -m "server-state: deployment ack ${REMOTE_SHA:0:12}" >/dev/null \
        || fail "cannot commit deployment acknowledgement"
    git push origin HEAD:server-state >/dev/null 2>&1 \
        || fail "cannot push deployment acknowledgement"
fi

printf 'HEALTHCHECK PASS: sha=%s\n' "$REMOTE_SHA"
