#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"

PROJECT="/opt/srv-control"
APP_USER="srv-control"
APP_GROUP="srv-control"
CONFIG_DIR="/etc/srv-control"
STATE_DIR="/var/lib/srv-control"
CACHE_DIR="/var/cache/srv-control"
LOG_DIR="/var/log/srv-control"
DEPLOY_STATE="/var/lib/srv-deployment"
AGENT_ROOT="/var/lib/srvcc-agent"
REPO_URL="https://github.com/filosoff31/srv-deployment.git"
INSTALL_LOG="/var/log/srv-control-install.log"

exec > >(tee -a "$INSTALL_LOG") 2>&1

log() {
    printf '%s %s\n' "$(date -Is)" "$*"
}

fail() {
    log "INSTALL FAIL: $*" >&2
    exit 1
}

[[ "$(id -u)" -eq 0 ]] || fail "run as root"
command -v apt-get >/dev/null 2>&1 || fail "Debian/Ubuntu with apt-get is required"
command -v systemctl >/dev/null 2>&1 || fail "systemd is required"

if [[ -e "$PROJECT" ]] && find "$PROJECT" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
    fail "$PROJECT already contains files; clean installer will not overwrite an existing Control Center"
fi

log "Installing operating-system dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    nginx \
    postgresql \
    postgresql-client \
    python3 \
    python3-pip \
    python3-venv \
    sudo

release_info="$(python3 - "$REPO_ROOT/deployment.json" <<'PY'
import hashlib
import json
import pathlib
import sys

config_path=pathlib.Path(sys.argv[1])
root=config_path.parent
config=json.loads(config_path.read_text(encoding="utf-8"))
release_id=config.get("release_id") or config.get("release")
release_path=config.get("release_path")
manifest_path=config.get("manifest")
if not all(isinstance(v,str) and v for v in (release_id,release_path,manifest_path)):
    raise SystemExit("invalid deployment metadata")
release_dir=(root/release_path).resolve()
manifest_file=(root/manifest_path).resolve()
if root.resolve() not in release_dir.parents:
    raise SystemExit("release_path escapes repository")
if root.resolve() not in manifest_file.parents:
    raise SystemExit("manifest path escapes repository")
manifest=json.loads(manifest_file.read_text(encoding="utf-8"))
version=manifest.get("release_version")
if not isinstance(version,str) or not version:
    raise SystemExit("release_version missing")
if manifest.get("release_id") != release_id:
    raise SystemExit("deployment/manifest release_id mismatch")
scripts=manifest.get("scripts") or {}
values=[]
for stage in ("apply","acceptance"):
    item=scripts.get(stage) or {}
    path=item.get("path")
    digest=item.get("sha256")
    if not isinstance(path,str) or not path or not isinstance(digest,str) or len(digest) != 64:
        raise SystemExit(f"invalid {stage} metadata")
    script=(release_dir/path).resolve()
    if release_dir not in script.parents:
        raise SystemExit(f"{stage} path escapes release directory")
    if not script.is_file():
        raise SystemExit(f"{stage} script missing")
    actual=hashlib.sha256(script.read_bytes()).hexdigest()
    if actual != digest.lower():
        raise SystemExit(f"{stage} sha256 mismatch")
    values.extend((str(script),actual))
print(release_id)
print(release_path)
print(version)
for value in values:
    print(value)
PY
)" || fail "active release metadata validation failed"
mapfile -t release_meta <<< "$release_info"
RELEASE_ID="${release_meta[0]:-}"
RELEASE_PATH="${release_meta[1]:-}"
RELEASE_VERSION="${release_meta[2]:-}"
APPLY_SCRIPT="${release_meta[3]:-}"
APPLY_SHA256="${release_meta[4]:-}"
ACCEPTANCE_SCRIPT="${release_meta[5]:-}"
ACCEPTANCE_SHA256="${release_meta[6]:-}"
PAYLOAD="$REPO_ROOT/$RELEASE_PATH/payload"

[[ -n "$RELEASE_ID" && -n "$RELEASE_VERSION" ]] || fail "release identity is empty"
[[ -d "$PAYLOAD/app" ]] || fail "active release application payload is missing"
[[ -d "$PAYLOAD/templates" ]] || fail "active release templates are missing"
[[ -d "$PAYLOAD/static" ]] || fail "active release static files are missing"
[[ -s "$PAYLOAD/requirements.lock" ]] || fail "active release requirements.lock is missing"
[[ -x "$APPLY_SCRIPT" ]] || fail "active release apply script is not executable"
[[ -x "$ACCEPTANCE_SCRIPT" ]] || fail "active release acceptance script is not executable"
log "Validated active release ${RELEASE_VERSION}: apply=${APPLY_SHA256} acceptance=${ACCEPTANCE_SHA256}"

systemctl enable --now postgresql.service

if ! getent group "$APP_GROUP" >/dev/null 2>&1; then
    groupadd --system "$APP_GROUP"
fi
if ! id "$APP_USER" >/dev/null 2>&1; then
    useradd \
        --system \
        --gid "$APP_GROUP" \
        --home-dir "$STATE_DIR" \
        --shell /usr/sbin/nologin \
        "$APP_USER"
fi

install -d -m 0750 -o root -g "$APP_GROUP" "$PROJECT" "$CONFIG_DIR"
install -d -m 0750 -o "$APP_USER" -g "$APP_GROUP" "$STATE_DIR" "$CACHE_DIR" "$LOG_DIR"
install -d -m 0750 -o root -g root "$DEPLOY_STATE" "$AGENT_ROOT"

log "Installing base application payload for ${RELEASE_VERSION}"
cp -a "$PAYLOAD/." "$PROJECT/"
find "$PROJECT" -type d -exec chmod 0750 {} +
find "$PROJECT" -type f -exec chmod 0640 {} +
chown -R root:"$APP_GROUP" "$PROJECT"

log "Creating Python virtual environment"
python3 -m venv "$PROJECT/venv"
"$PROJECT/venv/bin/python" -m pip install \
    --disable-pip-version-check \
    --no-input \
    -r "$PROJECT/requirements.lock"
chown -R root:"$APP_GROUP" "$PROJECT/venv"
find "$PROJECT/venv" -type d -exec chmod u+rwx,go+rx {} + || true

log "Preparing PostgreSQL role and database"
if ! runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='srv-control'" | grep -q 1; then
    runuser -u postgres -- createuser --login srv-control
fi
if ! runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_database WHERE datname='srv_control'" | grep -q 1; then
    runuser -u postgres -- createdb --owner=srv-control srv_control
fi

canonical_host="$(hostname -f 2>/dev/null || hostname)"
cat > "$CONFIG_DIR/control.toml" <<EOF
[application]
name = "Control Center"

[web]
canonical_host = "${canonical_host}"
bind_host = "127.0.0.1"
bind_port = 8876

[paths]
state = "${STATE_DIR}"
cache = "${CACHE_DIR}"
logs = "${LOG_DIR}"
EOF
chown root:"$APP_GROUP" "$CONFIG_DIR/control.toml"
chmod 0640 "$CONFIG_DIR/control.toml"

log "Applying base database migrations"
runuser -u "$APP_USER" -- env \
    PYTHONPATH="$PROJECT" \
    PYTHONDONTWRITEBYTECODE=1 \
    "$PROJECT/venv/bin/alembic" \
    -c "$PROJECT/alembic.ini" \
    upgrade head

log "Installing Control Center service"
cat > /etc/systemd/system/srv-control.service <<'EOF'
[Unit]
Description=Control Center
After=network-online.target postgresql.service
Wants=network-online.target
Requires=postgresql.service

[Service]
Type=simple
User=srv-control
Group=srv-control
WorkingDirectory=/opt/srv-control
Environment=PYTHONPATH=/opt/srv-control
Environment=PYTHONUNBUFFERED=1
Environment=PYTHONDONTWRITEBYTECODE=1
ExecStart=/opt/srv-control/venv/bin/python -m uvicorn app.main:app --host 127.0.0.1 --port 8876 --proxy-headers --forwarded-allow-ips=127.0.0.1 --workers 2 --timeout-worker-healthcheck 10
Restart=on-failure
RestartSec=3
TimeoutStopSec=30
UMask=0027
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=read-only
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
RestrictSUIDSGID=true
LockPersonality=true
ReadWritePaths=/var/lib/srv-control
ReadWritePaths=/var/log/srv-control
ReadWritePaths=/var/cache/srv-control

[Install]
WantedBy=multi-user.target
EOF

log "Configuring reverse proxy"
web_port=80
if command -v ss >/dev/null 2>&1 && ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq '(^|:|\])80$'; then
    web_port=8080
    if ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq '(^|:|\])8080$'; then
        web_port=8880
    fi
fi
rm -f /etc/nginx/sites-enabled/default
cat > /etc/nginx/sites-available/srv-control <<EOF
server {
    listen ${web_port} default_server;
    listen [::]:${web_port} default_server;
    server_name _;
    client_max_body_size 128m;
    location / {
        proxy_pass http://127.0.0.1:8876;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_read_timeout 3600s;
    }
}
EOF
ln -sfn /etc/nginx/sites-available/srv-control /etc/nginx/sites-enabled/srv-control
nginx -t

log "Installing authentication bootstrap and base privileged state"
bash "$SCRIPT_DIR/install-system-admin.sh"

systemctl daemon-reload
systemctl enable --now srv-control.service
systemctl restart nginx.service

current_sha="$(git -C "$REPO_ROOT" rev-parse HEAD)"
log "Applying complete active release contract ${RELEASE_VERSION}"
bash "$APPLY_SCRIPT" "$PROJECT" "$current_sha"

log "Running frozen release acceptance ${RELEASE_VERSION}"
bash "$ACCEPTANCE_SCRIPT" "$PROJECT" "$current_sha"

sync_time="$(date -Is)"
cat > "$DEPLOY_STATE/last-result.env" <<EOF
result=success
stage=acceptance
release_id=${RELEASE_ID}
remote_sha=${current_sha}
finished_at=${sync_time}
project=${PROJECT}
EOF
chmod 0640 "$DEPLOY_STATE/last-result.env"

python3 - "$STATE_DIR/deployment-status.json" "$RELEASE_VERSION" "$RELEASE_ID" "$sync_time" "$current_sha" <<'PY'
import json
import pathlib
import sys
from datetime import datetime, timezone
path=pathlib.Path(sys.argv[1])
path.write_text(json.dumps({
    "result":"success",
    "stage":"initial-install",
    "release_id":sys.argv[3],
    "version":sys.argv[2],
    "remote_sha":sys.argv[5],
    "release_synced_at":sys.argv[4],
    "deployment_finished_at":sys.argv[4],
    "healthchecked_at":datetime.now(timezone.utc).isoformat(),
},ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
PY
chown root:"$APP_GROUP" "$STATE_DIR/deployment-status.json"
chmod 0640 "$STATE_DIR/deployment-status.json"

log "Running final clean-install acceptance"
python3 - "$RELEASE_VERSION" "$current_sha" <<'PY'
import json
import sys
import time
import urllib.request
version=sys.argv[1]
sha=sys.argv[2]
last_error=None
for _ in range(40):
    try:
        with urllib.request.urlopen("http://127.0.0.1:8876/api/v1/health",timeout=5) as response:
            payload=json.load(response)
        release=payload.get("data",{}).get("release",{})
        if payload.get("ok") is True and release.get("version")==version and release.get("git_sha")==sha:
            raise SystemExit(0)
        last_error=repr(payload)
    except Exception as exc:
        last_error=repr(exc)
    time.sleep(1)
raise SystemExit(f"installer acceptance failed: {last_error}")
PY

systemctl is-active --quiet srv-control.service || fail "srv-control.service is not active"
systemctl is-active --quiet nginx.service || fail "nginx.service is not active"
systemctl is-enabled --quiet srvcc-github-agent.timer || fail "GitHub updater timer is not enabled"
systemctl is-active --quiet srvcc-github-agent.timer || fail "GitHub updater timer is not active"
systemctl is-active --quiet srv-control-system-agent.path || fail "system action watcher is not active"

server_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
server_ip="${server_ip:-127.0.0.1}"
if [[ "$web_port" -eq 80 ]]; then
    access_url="http://${server_ip}/"
else
    access_url="http://${server_ip}:${web_port}/"
fi

log "INSTALL PASS: Control Center ${RELEASE_VERSION}"
printf '\nCONTROL CENTER: INSTALLED\n'
printf 'release=%s\n' "$RELEASE_VERSION"
printf 'git_sha=%s\n' "$current_sha"
printf 'url=%s\n' "$access_url"
printf 'updater=srvcc-github-agent.timer\n'
printf 'install_log=%s\n' "$INSTALL_LOG"
