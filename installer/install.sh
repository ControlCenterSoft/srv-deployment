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
    python3-venv

release_info="$(python3 - "$REPO_ROOT/deployment.json" <<'PY'
import json
import pathlib
import sys

root=pathlib.Path(sys.argv[1]).parent
config=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
release_id=config.get("release_id") or config.get("release")
release_path=config.get("release_path")
manifest_path=config.get("manifest")
if not all(isinstance(v,str) and v for v in (release_id,release_path,manifest_path)):
    raise SystemExit("invalid deployment metadata")
manifest=json.loads((root/manifest_path).read_text(encoding="utf-8"))
version=manifest.get("release_version")
if not isinstance(version,str) or not version:
    raise SystemExit("release_version missing")
print(release_id)
print(release_path)
print(version)
PY
)"
mapfile -t release_meta <<< "$release_info"
RELEASE_ID="${release_meta[0]:-}"
RELEASE_PATH="${release_meta[1]:-}"
RELEASE_VERSION="${release_meta[2]:-}"
PAYLOAD="$REPO_ROOT/$RELEASE_PATH/payload"

[[ -d "$PAYLOAD/app" ]] || fail "active release application payload is missing"
[[ -d "$PAYLOAD/templates" ]] || fail "active release templates are missing"
[[ -d "$PAYLOAD/static" ]] || fail "active release static files are missing"
[[ -s "$PAYLOAD/requirements.lock" ]] || fail "active release requirements.lock is missing"

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

log "Installing consolidated release ${RELEASE_VERSION}"
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
name = "SRV Control Center"

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

log "Applying database migrations"
runuser -u "$APP_USER" -- env \
    PYTHONPATH="$PROJECT" \
    PYTHONDONTWRITEBYTECODE=1 \
    "$PROJECT/venv/bin/alembic" \
    -c "$PROJECT/alembic.ini" \
    upgrade head

log "Installing Control Center service"
cat > /etc/systemd/system/srv-control.service <<'EOF'
[Unit]
Description=SRV Control Center
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

log "Installing privileged system helpers"
bash "$SCRIPT_DIR/install-system-admin.sh"

current_sha="$(git -C "$REPO_ROOT" rev-parse HEAD)"
sync_time="$(date -Is)"
python3 - "$STATE_DIR/release.json" "$RELEASE_VERSION" "$RELEASE_ID" "$sync_time" "$current_sha" <<'PY'
import json
import pathlib
import sys
path=pathlib.Path(sys.argv[1])
path.write_text(json.dumps({
    "version":sys.argv[2],
    "release_id":sys.argv[3],
    "synced_at":sys.argv[4],
    "git_sha":sys.argv[5],
},ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
PY
chmod 0644 "$STATE_DIR/release.json"

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
chmod 0644 "$STATE_DIR/deployment-status.json"

systemctl daemon-reload
systemctl enable srv-control.service
systemctl restart srv-control.service
systemctl restart nginx.service

log "Installing release-fingerprint GitHub updater"
bash "$REPO_ROOT/bootstrap/configure-auto-updates.sh" \
    --repo "$REPO_URL" \
    --mode automatic \
    --interval-minutes 5 \
    --no-check-now

log "Running installation acceptance"
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
systemctl is-active --quiet srvcc-github-agent.timer || fail "GitHub updater timer is not active"

server_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
server_ip="${server_ip:-127.0.0.1}"
if [[ "$web_port" -eq 80 ]]; then
    access_url="http://${server_ip}/"
else
    access_url="http://${server_ip}:${web_port}/"
fi

log "INSTALL PASS: SRV Control Center ${RELEASE_VERSION}"
printf '\nSRV CONTROL CENTER: INSTALLED\n'
printf 'release=%s\n' "$RELEASE_VERSION"
printf 'git_sha=%s\n' "$current_sha"
printf 'url=%s\n' "$access_url"
printf 'updater=srvcc-github-agent.timer\n'
printf 'install_log=%s\n' "$INSTALL_LOG"
