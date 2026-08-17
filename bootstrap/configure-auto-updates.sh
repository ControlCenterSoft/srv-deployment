#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

REPO_URL="https://github.com/filosoff31/srv-deployment.git"
MODE="automatic"
INTERVAL_MINUTES=5
CHECK_NOW=0

PROJECT="/opt/srv-control"
STATE_DIR="/var/lib/srv-control"
RELEASE_META="${STATE_DIR}/release.json"
UPDATE_STATUS="${STATE_DIR}/github-update-status.json"

AGENT_ROOT="/var/lib/srvcc-agent"
DEPLOY_REPO="${AGENT_ROOT}/deploy-repo"
LAST_DEPLOYED_SHA="${AGENT_ROOT}/last-deployed-sha"
LAST_SEEN_SHA="${AGENT_ROOT}/last-seen-sha"
LAST_FINGERPRINT="${AGENT_ROOT}/last-release-fingerprint"
AGENT_BIN="/usr/local/sbin/srvcc-github-agent"
CONFIGURATOR_BIN="/usr/local/sbin/srvcc-configure-auto-updates"
STATE_PUBLISHER="/usr/local/sbin/srvcc-github-agent.state-publisher"
LOG="/var/log/srvcc-agent.log"
SERVICE="srvcc-github-agent.service"
TIMER="srvcc-github-agent.timer"

usage() {
    cat <<'EOF'
Usage:
  sudo ./configure-auto-updates.sh [options]

Options:
  --repo URL                 Git repository (default: filosoff31/srv-deployment)
  --mode automatic|manual    Automatic timer or manual checks only
  --interval-minutes N       Check interval for automatic mode, 1..1440
  --check-now                Run one update check after configuration
  --no-check-now             Do not run an immediate check (default)
  -h, --help                 Show this help

Supported installed Control Center versions: 0.8.0 and newer.
EOF
}

fail() {
    printf 'UPDATE CONFIG FAIL: %s\n' "$*" >&2
    exit 1
}

while (($#)); do
    case "$1" in
        --repo)
            [[ $# -ge 2 ]] || fail "--repo requires a value"
            REPO_URL="$2"
            shift 2
            ;;
        --mode)
            [[ $# -ge 2 ]] || fail "--mode requires a value"
            MODE="$2"
            shift 2
            ;;
        --interval-minutes)
            [[ $# -ge 2 ]] || fail "--interval-minutes requires a value"
            INTERVAL_MINUTES="$2"
            shift 2
            ;;
        --check-now)
            CHECK_NOW=1
            shift
            ;;
        --no-check-now)
            CHECK_NOW=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "unknown argument: $1"
            ;;
    esac
done

[[ "$(id -u)" -eq 0 ]] || fail "must run as root"
[[ "$MODE" == "automatic" || "$MODE" == "manual" ]] \
    || fail "mode must be automatic or manual"
[[ "$INTERVAL_MINUTES" =~ ^[0-9]+$ ]] \
    || fail "interval must be an integer"
(( INTERVAL_MINUTES >= 1 && INTERVAL_MINUTES <= 1440 )) \
    || fail "interval must be between 1 and 1440 minutes"

for command in git python3 systemctl sha256sum flock; do
    command -v "$command" >/dev/null 2>&1 \
        || fail "required command is missing: $command"
done

[[ -d "$PROJECT" ]] || fail "Control Center is not installed at $PROJECT"
[[ -s "$RELEASE_META" ]] || fail "release metadata is missing: $RELEASE_META"

python3 - "$RELEASE_META" <<'PY'
import json
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
version = str(payload.get("version") or "")

match = re.match(r"^(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$", version)
if not match:
    raise SystemExit(f"unsupported installed version format: {version!r}")

current = tuple(map(int, match.groups()))
if current < (0, 8, 0):
    raise SystemExit(
        f"automatic updater migration requires SRV Control Center >= 0.8.0; installed={version}"
    )
PY

install -d -m 0750 "$AGENT_ROOT"
install -d -m 0750 "$STATE_DIR"
touch "$LOG"
chmod 0640 "$LOG" || true

install -m 0755 "$0" "$CONFIGURATOR_BIN"

cat > "$AGENT_BIN" <<'AGENT'
#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

REPO_URL="${SRVCC_REPO_URL:-https://github.com/filosoff31/srv-deployment.git}"
PROJECT="/opt/srv-control"
STATE_DIR="/var/lib/srv-control"
RELEASE_META="${STATE_DIR}/release.json"
UPDATE_STATUS="${STATE_DIR}/github-update-status.json"

AGENT_ROOT="/var/lib/srvcc-agent"
DEPLOY_REPO="${AGENT_ROOT}/deploy-repo"
LAST_DEPLOYED_SHA="${AGENT_ROOT}/last-deployed-sha"
LAST_SEEN_SHA="${AGENT_ROOT}/last-seen-sha"
LAST_FINGERPRINT="${AGENT_ROOT}/last-release-fingerprint"
STATE_PUBLISHER="/usr/local/sbin/srvcc-github-agent.state-publisher"
LOG="/var/log/srvcc-agent.log"
LOCK="${AGENT_ROOT}/update.lock"

log() {
    printf '%s %s\n' "$(date -Is)" "$*" >> "$LOG"
}

write_status() {
    local result="$1"
    local detail="$2"
    local remote_sha="${3:-}"
    local release_id="${4:-}"
    local release_version="${5:-}"
    local update_available="${6:-false}"

    python3 - \
        "$UPDATE_STATUS" \
        "$result" \
        "$detail" \
        "$remote_sha" \
        "$release_id" \
        "$release_version" \
        "$update_available" \
        "$REPO_URL" <<'PY'
import json
import pathlib
import sys
import tempfile
from datetime import datetime, timezone

path = pathlib.Path(sys.argv[1])
payload = {
    "schema_version": 1,
    "checked_at": datetime.now(timezone.utc).isoformat(),
    "result": sys.argv[2],
    "detail": sys.argv[3],
    "remote_sha": sys.argv[4] or None,
    "release_id": sys.argv[5] or None,
    "release_version": sys.argv[6] or None,
    "update_available": sys.argv[7].lower() == "true",
    "source": sys.argv[8],
}
path.parent.mkdir(parents=True, exist_ok=True)
with tempfile.NamedTemporaryFile(
    mode="w",
    encoding="utf-8",
    dir=path.parent,
    prefix=path.name + ".tmp.",
    delete=False,
) as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
    tmp = pathlib.Path(handle.name)
tmp.chmod(0o644)
tmp.replace(path)
PY
}

publish_state() {
    local rc=0
    if [[ -x "$STATE_PUBLISHER" ]]; then
        "$STATE_PUBLISHER" || rc=$?
    fi
    return "$rc"
}

release_metadata() {
    local ref="$1"
    git -C "$DEPLOY_REPO" show "${ref}:deployment.json" \
        | python3 -c '
import json, sys
config=json.load(sys.stdin)
release_id=config.get("release_id") or config.get("release")
release_path=config.get("release_path")
manifest=config.get("manifest")
if not all(isinstance(x, str) and x for x in (release_id, release_path, manifest)):
    raise SystemExit("invalid deployment.json")
print(release_id)
print(release_path)
print(manifest)
'
}

manifest_version() {
    local ref="$1"
    local manifest="$2"
    git -C "$DEPLOY_REPO" show "${ref}:${manifest}" \
        | python3 -c '
import json, sys
manifest=json.load(sys.stdin)
value=manifest.get("release_version")
if not isinstance(value, str) or not value:
    raise SystemExit("release_version missing")
print(value)
'
}

current_release_value() {
    local key="$1"
    python3 - "$RELEASE_META" "$key" <<'PY'
import json
import pathlib
import sys
try:
    payload=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
except Exception:
    payload={}
value=payload.get(sys.argv[2])
print(value if isinstance(value, str) else "")
PY
}

exec 9>"$LOCK"
if ! flock -n 9; then
    log "Update check skipped: another updater run is active."
    exit 0
fi

install -d -m 0750 "$AGENT_ROOT"
touch "$LOG"
chmod 0640 "$LOG" || true

if [[ ! -d "$DEPLOY_REPO/.git" ]]; then
    rm -rf "$DEPLOY_REPO"
    git clone --no-tags --single-branch --branch main "$REPO_URL" "$DEPLOY_REPO" >/dev/null 2>&1 \
        || {
            log "Updater clone failed."
            write_status "error" "git clone failed"
            exit 1
        }
fi

git -C "$DEPLOY_REPO" remote set-url origin "$REPO_URL" >/dev/null 2>&1 || true
if ! git -C "$DEPLOY_REPO" fetch \
    --prune \
    origin \
    "+refs/heads/main:refs/remotes/origin/main" >/dev/null 2>&1
then
    log "Updater fetch failed."
    write_status "error" "git fetch failed"
    publish_state || true
    exit 1
fi

remote_sha="$(git -C "$DEPLOY_REPO" rev-parse origin/main)"
mapfile -t release_info < <(release_metadata origin/main)
release_id="${release_info[0]}"
release_path="${release_info[1]}"
manifest_path="${release_info[2]}"
release_version="$(manifest_version origin/main "$manifest_path")"
deployment_blob="$(git -C "$DEPLOY_REPO" rev-parse "origin/main:deployment.json")"
release_tree="$(git -C "$DEPLOY_REPO" rev-parse "origin/main:${release_path}")"
fingerprint="$(
    printf '%s\n%s\n%s\n%s\n' \
        "$release_id" \
        "$release_version" \
        "$deployment_blob" \
        "$release_tree" \
        | sha256sum \
        | awk '{print $1}'
)"

current_id="$(current_release_value release_id)"
current_version="$(current_release_value version)"
current_git_sha="$(current_release_value git_sha)"
stored_fingerprint="$(cat "$LAST_FINGERPRINT" 2>/dev/null || true)"

if [[ -z "$stored_fingerprint" \
      && "$current_id" == "$release_id" \
      && "$current_version" == "$release_version" \
      && -n "$current_git_sha" ]]
then
    old_tree="$(
        git -C "$DEPLOY_REPO" rev-parse "${current_git_sha}:${release_path}" 2>/dev/null \
            || true
    )"
    if [[ -n "$old_tree" && "$old_tree" == "$release_tree" ]]; then
        printf '%s\n' "$fingerprint" > "$LAST_FINGERPRINT"
        printf '%s\n' "$remote_sha" > "$LAST_SEEN_SHA"
        printf '%s\n' "$current_git_sha" > "$LAST_DEPLOYED_SHA"
        chmod 0640 "$LAST_FINGERPRINT" "$LAST_SEEN_SHA" "$LAST_DEPLOYED_SHA"
        write_status \
            "ok" \
            "existing release fingerprint adopted; no product reapply required" \
            "$remote_sha" \
            "$release_id" \
            "$release_version" \
            "false"
        log "Updater migration adopted existing release ${release_id} ${release_version}."
        publish_state || true
        exit 0
    fi
fi

if [[ "$stored_fingerprint" == "$fingerprint" \
      && "$current_id" == "$release_id" \
      && "$current_version" == "$release_version" ]]
then
    printf '%s\n' "$remote_sha" > "$LAST_SEEN_SHA"
    chmod 0640 "$LAST_SEEN_SHA"
    write_status \
        "ok" \
        "repository checked; active product release unchanged" \
        "$remote_sha" \
        "$release_id" \
        "$release_version" \
        "false"
    publish_state || true
    exit 0
fi

write_status \
    "update-available" \
    "active product release differs from installed release" \
    "$remote_sha" \
    "$release_id" \
    "$release_version" \
    "true"

git -C "$DEPLOY_REPO" reset --hard origin/main >/dev/null
git -C "$DEPLOY_REPO" clean -fd >/dev/null 2>&1 || true

[[ -x "$DEPLOY_REPO/deploy/deploy.sh" ]] \
    || {
        log "deploy/deploy.sh is missing."
        write_status "error" "deploy/deploy.sh is missing" "$remote_sha" "$release_id" "$release_version" "true"
        publish_state || true
        exit 1
    }

log "Product update ${release_id} ${release_version} at ${remote_sha}; starting deployment."

if ! bash \
    "$DEPLOY_REPO/deploy/deploy.sh" \
    "$PROJECT" \
    "$remote_sha" >> "$LOG" 2>&1
then
    log "Deployment failed for ${remote_sha}."
    write_status "error" "deployment failed" "$remote_sha" "$release_id" "$release_version" "true"
    publish_state || true
    exit 1
fi

if [[ -x "$DEPLOY_REPO/deploy/healthcheck.sh" ]]; then
    if ! bash \
        "$DEPLOY_REPO/deploy/healthcheck.sh" \
        "$PROJECT" \
        "$remote_sha" >> "$LOG" 2>&1
    then
        log "Deployment healthcheck failed for ${remote_sha}."
        write_status "error" "deployment healthcheck failed" "$remote_sha" "$release_id" "$release_version" "true"
        publish_state || true
        exit 1
    fi
fi

printf '%s\n' "$remote_sha" > "$LAST_DEPLOYED_SHA"
printf '%s\n' "$remote_sha" > "$LAST_SEEN_SHA"
printf '%s\n' "$fingerprint" > "$LAST_FINGERPRINT"
chmod 0640 "$LAST_DEPLOYED_SHA" "$LAST_SEEN_SHA" "$LAST_FINGERPRINT"

write_status \
    "updated" \
    "product release applied and accepted" \
    "$remote_sha" \
    "$release_id" \
    "$release_version" \
    "false"
log "Deployment successful for ${remote_sha}; release=${release_id} version=${release_version}."
publish_state || true
AGENT

chmod 0755 "$AGENT_BIN"

cat > "/etc/systemd/system/${SERVICE}" <<EOF
[Unit]
Description=SRV Control Center GitHub updater
After=network-online.target srv-control.service
Wants=network-online.target

[Service]
Type=oneshot
User=root
Group=root
Environment=SRVCC_REPO_URL=${REPO_URL}
ExecStart=${AGENT_BIN}
EOF

cat > "/etc/systemd/system/${TIMER}" <<EOF
[Unit]
Description=Check GitHub for SRV Control Center product updates

[Timer]
OnBootSec=2min
OnUnitActiveSec=${INTERVAL_MINUTES}min
RandomizedDelaySec=30s
AccuracySec=15s
Persistent=true
Unit=${SERVICE}

[Install]
WantedBy=timers.target
EOF

if [[ ! -d "$DEPLOY_REPO/.git" ]]; then
    rm -rf "$DEPLOY_REPO"
    git clone --no-tags --single-branch --branch main "$REPO_URL" "$DEPLOY_REPO" \
        || fail "cannot clone update source"
else
    git -C "$DEPLOY_REPO" remote set-url origin "$REPO_URL" || true
fi

systemctl daemon-reload
systemctl enable "$SERVICE" >/dev/null 2>&1 || true

if [[ "$MODE" == "automatic" ]]; then
    systemctl enable "$TIMER" >/dev/null 2>&1
    systemctl restart "$TIMER"
else
    systemctl disable --now "$TIMER" >/dev/null 2>&1 || true
fi

python3 - "$STATE_DIR/github-update-config.json" "$REPO_URL" "$MODE" "$INTERVAL_MINUTES" <<'PY'
import json
import pathlib
import sys
import tempfile

path=pathlib.Path(sys.argv[1])
payload={
    "schema_version": 1,
    "source": sys.argv[2],
    "mode": sys.argv[3],
    "interval_minutes": int(sys.argv[4]),
}
path.parent.mkdir(parents=True, exist_ok=True)
with tempfile.NamedTemporaryFile(
    mode="w",
    encoding="utf-8",
    dir=path.parent,
    prefix=path.name + ".tmp.",
    delete=False,
) as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
    tmp=pathlib.Path(handle.name)
tmp.chmod(0o644)
tmp.replace(path)
PY

if (( CHECK_NOW )); then
    if systemctl is-active --quiet "$SERVICE"; then
        printf 'UPDATE CONFIG: updater is already running; immediate check skipped.\n'
    else
        systemctl start "$SERVICE"
    fi
fi

printf 'UPDATE CONFIG PASS\n'
printf 'source=%s\n' "$REPO_URL"
printf 'mode=%s\n' "$MODE"
printf 'interval_minutes=%s\n' "$INTERVAL_MINUTES"
printf 'service=%s\n' "$SERVICE"
printf 'timer=%s\n' "$TIMER"
