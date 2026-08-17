#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

NEW_REPO_URL="https://github.com/filosoff31/srv-deployment.git"
AGENT_ROOT="/var/lib/srvcc-agent"
DEPLOY_REPO="${AGENT_ROOT}/deploy-repo"
LAST_SHA="${AGENT_ROOT}/last-deployed-sha"
AGENT_BIN="/usr/local/sbin/srvcc-github-agent"
STATE_PUBLISHER="/usr/local/sbin/srvcc-github-agent.state-publisher"
TIMER="srvcc-github-agent.timer"
SERVICE="srvcc-github-agent.service"
LOG="/var/log/srvcc-agent.log"

log() {
    printf '%s %s\n' "$(date -Is)" "$*" | tee -a "$LOG"
}

fail() {
    log "REPAIR FAIL: $*" >&2
    exit 1
}

[[ "$(id -u)" -eq 0 ]] || fail "must run as root"
command -v git >/dev/null 2>&1 || fail "git is required"
command -v systemctl >/dev/null 2>&1 || fail "systemctl is required"

install -d -m 0750 "$AGENT_ROOT"
touch "$LOG"
chmod 0640 "$LOG" || true

log "REPAIR START: switching deployment source to ${NEW_REPO_URL}"

systemctl stop "$TIMER" >/dev/null 2>&1 || true
systemctl stop "$SERVICE" >/dev/null 2>&1 || true

# Preserve the currently working state publisher exactly once.
if [[ ! -x "$STATE_PUBLISHER" ]]; then
    [[ -x "$AGENT_BIN" ]] || fail "current agent is missing: ${AGENT_BIN}"
    cp -a "$AGENT_BIN" "$STATE_PUBLISHER"
    chmod 0755 "$STATE_PUBLISHER"
    log "Saved existing state publisher as ${STATE_PUBLISHER}"
fi

# The old deploy checkout points at filosoff999/srv-control-center. Keep a backup
# for diagnostics, then create a clean checkout of the authoritative repository.
if [[ -e "$DEPLOY_REPO" ]]; then
    backup="${DEPLOY_REPO}.backup.$(date +%Y%m%dT%H%M%S)"
    mv "$DEPLOY_REPO" "$backup"
    log "Backed up previous deploy checkout to ${backup}"
fi

git clone --no-tags --single-branch --branch main "$NEW_REPO_URL" "$DEPLOY_REPO" >/dev/null 2>&1 \
    || fail "cannot clone ${NEW_REPO_URL}"

git -C "$DEPLOY_REPO" fetch --prune origin "+refs/heads/main:refs/remotes/origin/main" >/dev/null 2>&1 \
    || fail "cannot fetch origin/main"
git -C "$DEPLOY_REPO" checkout -B main origin/main >/dev/null 2>&1 \
    || fail "cannot checkout origin/main"

[[ -f "$DEPLOY_REPO/deploy/deploy.sh" ]] || fail "deploy/deploy.sh is absent in new repository"
chmod 0755 "$DEPLOY_REPO/deploy/deploy.sh"
[[ ! -f "$DEPLOY_REPO/deploy/healthcheck.sh" ]] || chmod 0755 "$DEPLOY_REPO/deploy/healthcheck.sh"

rm -f "$LAST_SHA"

cat > "$AGENT_BIN" <<'AGENT'
#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

NEW_REPO_URL="https://github.com/filosoff31/srv-deployment.git"
AGENT_ROOT="/var/lib/srvcc-agent"
DEPLOY_REPO="${AGENT_ROOT}/deploy-repo"
LAST_SHA="${AGENT_ROOT}/last-deployed-sha"
STATE_PUBLISHER="/usr/local/sbin/srvcc-github-agent.state-publisher"
PROJECT="/opt/srv-control"
LOG="/var/log/srvcc-agent.log"

log() {
    printf '%s %s\n' "$(date -Is)" "$*" >> "$LOG"
}

run_deployment() {
    local remote_sha last_sha=""

    if [[ ! -d "$DEPLOY_REPO/.git" ]]; then
        log "Deploy repository is missing; cloning ${NEW_REPO_URL}."
        rm -rf "$DEPLOY_REPO"
        git clone --no-tags --single-branch --branch main "$NEW_REPO_URL" "$DEPLOY_REPO" >/dev/null 2>&1 \
            || { log "Deployment fetch failed: cannot clone repository."; return 1; }
    fi

    git -C "$DEPLOY_REPO" remote set-url origin "$NEW_REPO_URL" >/dev/null 2>&1 || true
    git -C "$DEPLOY_REPO" fetch --prune origin "+refs/heads/main:refs/remotes/origin/main" >/dev/null 2>&1 \
        || { log "Deployment fetch failed: cannot fetch origin/main."; return 1; }

    remote_sha="$(git -C "$DEPLOY_REPO" rev-parse origin/main 2>/dev/null)" \
        || { log "Deployment fetch failed: origin/main cannot be resolved."; return 1; }

    [[ -f "$LAST_SHA" ]] && last_sha="$(tr -d '\r\n' < "$LAST_SHA")"

    if [[ "$remote_sha" == "$last_sha" ]]; then
        return 0
    fi

    git -C "$DEPLOY_REPO" reset --hard origin/main >/dev/null 2>&1 \
        || { log "Deployment checkout failed for ${remote_sha}."; return 1; }
    git -C "$DEPLOY_REPO" clean -fd >/dev/null 2>&1 || true

    if [[ ! -f "$DEPLOY_REPO/deploy/deploy.sh" ]]; then
        log "New main commit ${remote_sha}, but deploy/deploy.sh is absent."
        return 1
    fi

    log "New main commit ${remote_sha}; starting deploy/deploy.sh."
    if ! bash "$DEPLOY_REPO/deploy/deploy.sh" "$PROJECT" "$remote_sha" >> "$LOG" 2>&1; then
        log "Deployment failed for ${remote_sha}."
        return 1
    fi

    if [[ -f "$DEPLOY_REPO/deploy/healthcheck.sh" ]]; then
        if ! bash "$DEPLOY_REPO/deploy/healthcheck.sh" "$PROJECT" "$remote_sha" >> "$LOG" 2>&1; then
            log "Deployment healthcheck failed for ${remote_sha}."
            return 1
        fi
    fi

    printf '%s\n' "$remote_sha" > "$LAST_SHA"
    chmod 0640 "$LAST_SHA"
    log "Deployment successful for ${remote_sha}."
}

deploy_rc=0
run_deployment || deploy_rc=$?

# Keep the proven server-state publisher intact. Deployment failures must not
# prevent state telemetry from reaching the server-state branch.
state_rc=0
if [[ -x "$STATE_PUBLISHER" ]]; then
    "$STATE_PUBLISHER" || state_rc=$?
else
    log "State publisher missing: ${STATE_PUBLISHER}."
    state_rc=1
fi

if (( deploy_rc != 0 )); then
    exit "$deploy_rc"
fi
exit "$state_rc"
AGENT

chmod 0755 "$AGENT_BIN"

systemctl daemon-reload
systemctl enable "$TIMER" >/dev/null 2>&1 || true
systemctl start "$TIMER" >/dev/null 2>&1 || true

log "REPAIR: forcing first deployment run"
if ! systemctl start "$SERVICE"; then
    log "REPAIR FAIL: first agent run failed"
    systemctl status "$SERVICE" --no-pager -l || true
    exit 1
fi

sleep 2

remote_sha="$(git -C "$DEPLOY_REPO" rev-parse origin/main 2>/dev/null || true)"
last_sha="$(cat "$LAST_SHA" 2>/dev/null || true)"

[[ -n "$remote_sha" ]] || fail "origin/main is unresolved after repair"
[[ "$remote_sha" == "$last_sha" ]] || fail "deployment was not acknowledged: remote=${remote_sha} last=${last_sha:-NONE}"
[[ -s "$PROJECT/DEPLOYMENT_STATUS.txt" ]] || fail "channel probe marker was not created"

grep -Fxq 'result=success' "$PROJECT/DEPLOYMENT_STATUS.txt" \
    || fail "channel probe marker does not report success"
grep -Fxq "remote_sha=${remote_sha}" "$PROJECT/DEPLOYMENT_STATUS.txt" \
    || fail "channel probe marker SHA mismatch"

log "REPAIR PASS: deployment channel is operational at ${remote_sha}"
printf '\nSRV DEPLOYMENT CHANNEL: PASS\n'
printf 'main_sha=%s\n' "$remote_sha"
printf 'last_deployed_sha=%s\n' "$last_sha"
printf 'probe=%s\n' "$PROJECT/DEPLOYMENT_STATUS.txt"
