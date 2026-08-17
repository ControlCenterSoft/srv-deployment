#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

NEW_REPO_URL="https://github.com/filosoff31/srv-deployment.git"
AGENT_ROOT="/var/lib/srvcc-agent"
DEPLOY_REPO="${AGENT_ROOT}/deploy-repo"
LAST_SHA="${AGENT_ROOT}/last-deployed-sha"
AGENT_BIN="/usr/local/sbin/srvcc-github-agent"
STATE_PUBLISHER="/usr/local/sbin/srvcc-github-agent.state-publisher"
PROJECT="/opt/srv-control"
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
[[ -d "$PROJECT" ]] || fail "project is missing: $PROJECT"
command -v git >/dev/null 2>&1 || fail "git is required"
command -v systemctl >/dev/null 2>&1 || fail "systemctl is required"

install -d -m 0750 "$AGENT_ROOT"
touch "$LOG"
chmod 0640 "$LOG" || true

log "REPAIR START: switching deployment source to ${NEW_REPO_URL}"

systemctl stop "$TIMER" >/dev/null 2>&1 || true
systemctl stop "$SERVICE" >/dev/null 2>&1 || true

if [[ ! -x "$STATE_PUBLISHER" && -x "$AGENT_BIN" ]]; then
    cp -a "$AGENT_BIN" "$STATE_PUBLISHER"
    chmod 0755 "$STATE_PUBLISHER"
    log "Saved existing state publisher as ${STATE_PUBLISHER}"
fi

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

[[ -f "$DEPLOY_REPO/deploy/deploy.sh" ]] || fail "deploy/deploy.sh is absent"
chmod 0755 "$DEPLOY_REPO/deploy/deploy.sh"
[[ ! -f "$DEPLOY_REPO/deploy/healthcheck.sh" ]] || chmod 0755 "$DEPLOY_REPO/deploy/healthcheck.sh"

rm -f "$LAST_SHA"

cat > "$AGENT_BIN" <<'AGENT'
#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

REPO_URL="https://github.com/filosoff31/srv-deployment.git"
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
    local remote_sha
    local last_sha=""

    if [[ ! -d "$DEPLOY_REPO/.git" ]]; then
        rm -rf "$DEPLOY_REPO"
        git clone --no-tags --single-branch --branch main "$REPO_URL" "$DEPLOY_REPO" >/dev/null 2>&1 \
            || { log "Deployment clone failed."; return 1; }
    fi

    git -C "$DEPLOY_REPO" remote set-url origin "$REPO_URL" >/dev/null 2>&1 || true
    git -C "$DEPLOY_REPO" fetch --prune origin "+refs/heads/main:refs/remotes/origin/main" >/dev/null 2>&1 \
        || { log "Deployment fetch failed."; return 1; }

    remote_sha="$(git -C "$DEPLOY_REPO" rev-parse origin/main)" \
        || { log "origin/main cannot be resolved."; return 1; }

    [[ -f "$LAST_SHA" ]] && last_sha="$(tr -d '\r\n' < "$LAST_SHA")"

    if [[ "$remote_sha" == "$last_sha" ]]; then
        return 0
    fi

    git -C "$DEPLOY_REPO" reset --hard origin/main >/dev/null 2>&1 \
        || { log "Deployment checkout failed for ${remote_sha}."; return 1; }
    git -C "$DEPLOY_REPO" clean -fd >/dev/null 2>&1 || true

    [[ -f "$DEPLOY_REPO/deploy/deploy.sh" ]] \
        || { log "deploy/deploy.sh is missing."; return 1; }

    log "New main commit ${remote_sha}; starting deployment."

    bash "$DEPLOY_REPO/deploy/deploy.sh" "$PROJECT" "$remote_sha" >> "$LOG" 2>&1 \
        || { log "Deployment failed for ${remote_sha}."; return 1; }

    if [[ -f "$DEPLOY_REPO/deploy/healthcheck.sh" ]]; then
        bash "$DEPLOY_REPO/deploy/healthcheck.sh" "$PROJECT" "$remote_sha" >> "$LOG" 2>&1 \
            || { log "Deployment healthcheck failed for ${remote_sha}."; return 1; }
    fi

    printf '%s\n' "$remote_sha" > "$LAST_SHA"
    chmod 0640 "$LAST_SHA"
    log "Deployment successful for ${remote_sha}."
}

deploy_rc=0
run_deployment || deploy_rc=$?

state_rc=0
if [[ -x "$STATE_PUBLISHER" ]]; then
    "$STATE_PUBLISHER" || state_rc=$?
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

log "REPAIR: forcing deployment/healthcheck"
systemctl start "$SERVICE" || fail "first agent run failed"

remote_sha="$(git -C "$DEPLOY_REPO" rev-parse origin/main 2>/dev/null || true)"
last_sha="$(cat "$LAST_SHA" 2>/dev/null || true)"

[[ -n "$remote_sha" ]] || fail "origin/main is unresolved"
[[ "$remote_sha" == "$last_sha" ]] \
    || fail "deployment was not acknowledged: remote=${remote_sha} last=${last_sha:-NONE}"
systemctl is-active --quiet srv-control.service \
    || fail "srv-control.service is not active"

if [[ -x "$DEPLOY_REPO/deploy/healthcheck.sh" ]]; then
    bash "$DEPLOY_REPO/deploy/healthcheck.sh" "$PROJECT" "$remote_sha" \
        || fail "final deployment healthcheck failed"
fi

log "REPAIR PASS: deployment channel is operational at ${remote_sha}"

printf '\nSRV DEPLOYMENT CHANNEL: PASS\n'
printf 'main_sha=%s\n' "$remote_sha"
printf 'last_deployed_sha=%s\n' "$last_sha"
printf 'healthcheck=%s\n' "$DEPLOY_REPO/deploy/healthcheck.sh"
