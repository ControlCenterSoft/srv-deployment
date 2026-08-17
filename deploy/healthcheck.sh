#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
STATUS_FILE="/var/lib/srv-deployment/last-result.env"
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

fail() {
    printf 'HEALTHCHECK FAIL: %s\n' "$*" >&2
    exit 1
}

cleanup_worktree() {
    if [[ -n "${ACK_WORKTREE:-}" ]]; then
        git -C "$REPO_ROOT" worktree remove --force "$ACK_WORKTREE" >/dev/null 2>&1 || true
        rm -rf -- "$ACK_WORKTREE" >/dev/null 2>&1 || true
    fi
}

[[ "$(id -u)" -eq 0 ]] || fail "must run as root"
[[ -d "$PROJECT" ]] || fail "project directory missing: $PROJECT"
[[ -s "$STATUS_FILE" ]] || fail "deployment status file is missing"
[[ -d "${REPO_ROOT}/.git" ]] || fail "deployment repository is missing"
command -v git >/dev/null 2>&1 || fail "git is required"
systemctl is-active --quiet srv-control.service || fail "srv-control.service is not active"

grep -Fxq 'result=success' "$STATUS_FILE" || fail "last deployment result is not success"
if [[ "$REMOTE_SHA" != "unknown" ]]; then
    grep -Fxq "remote_sha=${REMOTE_SHA}" "$STATUS_FILE" || fail "status SHA does not match requested commit"
fi

git -C "$REPO_ROOT" fetch origin server-state >/dev/null 2>&1 || fail "cannot fetch server-state"

ACK_WORKTREE="$(mktemp -d /var/lib/srv-deployment/ack-worktree.XXXXXX)"
trap cleanup_worktree EXIT

git -C "$REPO_ROOT" worktree add --detach "$ACK_WORKTREE" origin/server-state >/dev/null 2>&1 \
    || fail "cannot create acknowledgement worktree"

ACK_FILE="${ACK_WORKTREE}/deployment-status.env"
tmp="$(mktemp "${ACK_FILE}.tmp.XXXXXX")"
cat "$STATUS_FILE" > "$tmp"
printf 'acknowledged_at=%s\n' "$(date -Is)" >> "$tmp"
printf 'hostname=%s\n' "$(hostname -f 2>/dev/null || hostname)" >> "$tmp"
chmod 0644 "$tmp"
mv -f "$tmp" "$ACK_FILE"

git -C "$ACK_WORKTREE" add -- deployment-status.env
if ! git -C "$ACK_WORKTREE" diff --cached --quiet; then
    git -C "$ACK_WORKTREE" \
        -c user.name='SRV Deployment' \
        -c user.email='srv-deployment@localhost' \
        commit -m "server-state: deployment ack ${REMOTE_SHA:0:12}" >/dev/null \
        || fail "cannot commit deployment acknowledgement"
    git -C "$ACK_WORKTREE" push origin HEAD:server-state >/dev/null 2>&1 \
        || fail "cannot push deployment acknowledgement"
fi

cleanup_worktree
ACK_WORKTREE=""
trap - EXIT

printf 'HEALTHCHECK PASS: sha=%s\n' "$REMOTE_SHA"
