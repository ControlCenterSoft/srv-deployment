#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

REPO_URL="https://github.com/filosoff31/srv-deployment.git"
EXPECTED_VERSION="1.0.0"
UPDATE_INTERVAL_MINUTES="${UPDATE_INTERVAL_MINUTES:-5}"
PROJECT="/opt/srv-control"
APP_USER="srv-control"
APP_GROUP="srv-control"
STATE_DIR="/var/lib/srv-control"
CONFIG_DIR="/etc/srv-control"
CACHE_DIR="/var/cache/srv-control"
LOG_DIR="/var/log/srv-control"
DEPLOY_STATE="/var/lib/srv-deployment"
AGENT_ROOT="/var/lib/srvcc-agent"
TMP_ROOT="$(mktemp -d /tmp/srvcc-reinstall-1.0.0.XXXXXX)"
PUBLISHER_BACKUP="${TMP_ROOT}/srvcc-github-agent.state-publisher"

log() {
    printf '%s %s\n' "$(date -Is)" "$*"
}

fail() {
    log "REINSTALL FAIL: $*" >&2
    exit 1
}

cleanup_tmp() {
    rm -rf "$TMP_ROOT"
}
trap cleanup_tmp EXIT

[[ "$(id -u)" -eq 0 ]] || fail "run as root"
command -v apt-get >/dev/null 2>&1 || fail "Debian/Ubuntu with apt-get is required"
command -v systemctl >/dev/null 2>&1 || fail "systemd is required"
[[ "$UPDATE_INTERVAL_MINUTES" =~ ^[0-9]+$ ]] || fail "UPDATE_INTERVAL_MINUTES must be an integer"
(( UPDATE_INTERVAL_MINUTES >= 1 && UPDATE_INTERVAL_MINUTES <= 1440 )) \
    || fail "UPDATE_INTERVAL_MINUTES must be between 1 and 1440"

cat <<'EOF'

WARNING: DESTRUCTIVE REINSTALL
This procedure permanently removes the current SRV Control Center installation,
its PostgreSQL database srv_control, database role srv-control, Control Center
configuration/state/cache/logs, deployment state and GitHub updater state.

It does NOT remove Samba/AD, PXE data, Docker, Minecraft, torrent services,
AdGuard VPN itself, user shares, or other unrelated server services.

Type exactly: REINSTALL-1.0.0
EOF
read -r confirmation
[[ "$confirmation" == "REINSTALL-1.0.0" ]] || fail "confirmation did not match"

log "Installing bootstrap dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
    ca-certificates curl git postgresql-client python3

# Preserve only the optional server-state publisher executable. It is not part
# of the 1.0.0 clean-install payload, but keeping it allows the existing
# server-state reporting channel to survive the clean reinstall when present.
if [[ -x /usr/local/sbin/srvcc-github-agent.state-publisher ]]; then
    cp -a /usr/local/sbin/srvcc-github-agent.state-publisher "$PUBLISHER_BACKUP"
fi

log "Stopping Control Center and all updater/system helper units"
for unit in \
    srvcc-github-agent.timer \
    srvcc-github-agent.service \
    srv-deploy-agent.timer \
    srv-deploy-agent.service \
    srv-control-adguard-monitor.timer \
    srv-control-adguard-monitor.service \
    srv-control-system-agent.path \
    srv-control-system-agent.service \
    srv-control-os-update.service \
    srv-control.service
do
    systemctl disable --now "$unit" >/dev/null 2>&1 || true
done

if id "$APP_USER" >/dev/null 2>&1; then
    pkill -TERM -u "$APP_USER" >/dev/null 2>&1 || true
    sleep 1
    pkill -KILL -u "$APP_USER" >/dev/null 2>&1 || true
fi

log "Removing Control Center systemd units and privileged helpers"
rm -f \
    /etc/systemd/system/srv-control.service \
    /etc/systemd/system/srv-control-system-agent.service \
    /etc/systemd/system/srv-control-system-agent.path \
    /etc/systemd/system/srv-control-os-update.service \
    /etc/systemd/system/srv-control-adguard-monitor.service \
    /etc/systemd/system/srv-control-adguard-monitor.timer \
    /etc/systemd/system/srvcc-github-agent.service \
    /etc/systemd/system/srvcc-github-agent.timer \
    /etc/systemd/system/srv-deploy-agent.service \
    /etc/systemd/system/srv-deploy-agent.timer

rm -f \
    /usr/local/libexec/srv-control-system-agent \
    /usr/local/libexec/srv-control-os-update \
    /usr/local/libexec/srv-control-adguard-monitor \
    /usr/local/sbin/srvcc-github-agent \
    /usr/local/sbin/srvcc-configure-auto-updates \
    /usr/local/sbin/srv-deploy-agent

systemctl daemon-reload
systemctl reset-failed >/dev/null 2>&1 || true

log "Removing Control Center reverse-proxy configuration"
rm -f /etc/nginx/sites-enabled/srv-control /etc/nginx/sites-available/srv-control

log "Dropping Control Center PostgreSQL database and role"
if command -v psql >/dev/null 2>&1 && id postgres >/dev/null 2>&1; then
    systemctl start postgresql.service >/dev/null 2>&1 || true

    runuser -u postgres -- psql -v ON_ERROR_STOP=1 -d postgres <<'SQL'
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = 'srv_control'
  AND pid <> pg_backend_pid();
DROP DATABASE IF EXISTS srv_control;
DROP ROLE IF EXISTS "srv-control";
SQL
else
    log "PostgreSQL tools/user not present; database cleanup skipped because no local PostgreSQL instance is available"
fi

log "Removing Control Center application, configuration, state and updater state"
rm -rf \
    "$PROJECT" \
    "$CONFIG_DIR" \
    "$STATE_DIR" \
    "$CACHE_DIR" \
    "$LOG_DIR" \
    "$DEPLOY_STATE" \
    "$AGENT_ROOT"

rm -f \
    /var/log/srvcc-agent.log \
    /var/log/srv-control-install.log \
    /tmp/srvcc-configure-auto-updates.sh

if id "$APP_USER" >/dev/null 2>&1; then
    userdel "$APP_USER" >/dev/null 2>&1 || true
fi
if getent group "$APP_GROUP" >/dev/null 2>&1; then
    groupdel "$APP_GROUP" >/dev/null 2>&1 || true
fi

log "Cloning GitHub source and pinning installation to active release 1.0.0"
git clone --depth 1 --branch main "$REPO_URL" "$TMP_ROOT/repo"
REPO_ROOT="$TMP_ROOT/repo"

active_version="$(python3 - "$REPO_ROOT/deployment.json" "$REPO_ROOT" <<'PY'
import json
import pathlib
import sys

config_path = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2])
config = json.loads(config_path.read_text(encoding="utf-8"))
manifest = config.get("manifest")
if not isinstance(manifest, str) or not manifest:
    raise SystemExit("deployment.json does not define manifest")
manifest_path = (root / manifest).resolve()
payload = json.loads(manifest_path.read_text(encoding="utf-8"))
version = payload.get("release_version")
if not isinstance(version, str) or not version:
    raise SystemExit("release_version missing from manifest")
print(version)
PY
)"

[[ "$active_version" == "$EXPECTED_VERSION" ]] \
    || fail "GitHub active release is ${active_version}; expected exactly ${EXPECTED_VERSION}"

[[ -x "$REPO_ROOT/installer/install.sh" ]] \
    || fail "installer/install.sh is missing or not executable"

log "Running clean SRV Control Center ${EXPECTED_VERSION} installer"
bash "$REPO_ROOT/installer/install.sh"

log "Populating clean database with baseline Control Center settings"
runuser -u postgres -- psql -v ON_ERROR_STOP=1 -d srv_control <<SQL
INSERT INTO settings (key, value, description)
VALUES
(
  'control_center.installation',
  jsonb_build_object(
    'release', '${EXPECTED_VERSION}',
    'source', '${REPO_URL}',
    'install_type', 'fresh'
  ),
  'Fresh SRV Control Center installation baseline'
),
(
  'control_center.github_updates',
  jsonb_build_object(
    'mode', 'automatic',
    'interval_minutes', ${UPDATE_INTERVAL_MINUTES},
    'source', '${REPO_URL}'
  ),
  'GitHub product update baseline'
),
(
  'control_center.os_updates',
  jsonb_build_object(
    'mode', 'manual',
    'interval_hours', 24
  ),
  'Operating-system package update baseline'
),
(
  'control_center.backups',
  jsonb_build_object(
    'scheduled', false,
    'backup_before_update', true
  ),
  'Backup policy baseline'
)
ON CONFLICT (key)
DO UPDATE SET
  value = EXCLUDED.value,
  description = EXCLUDED.description,
  updated_at = now();
SQL

log "Reconfiguring automatic GitHub updater"
bash "$REPO_ROOT/bootstrap/configure-auto-updates.sh" \
    --repo "$REPO_URL" \
    --mode automatic \
    --interval-minutes "$UPDATE_INTERVAL_MINUTES" \
    --no-check-now

if [[ -f "$PUBLISHER_BACKUP" ]]; then
    install -m 0755 -o root -g root \
        "$PUBLISHER_BACKUP" \
        /usr/local/sbin/srvcc-github-agent.state-publisher
fi

log "Running immediate updater self-test"
if ! systemctl start srvcc-github-agent.service; then
    systemctl --no-pager --full status srvcc-github-agent.service || true
    journalctl --no-pager -n 120 -u srvcc-github-agent.service || true
    fail "GitHub updater self-test failed"
fi

log "Verifying Control Center, database and updater"
systemctl is-active --quiet srv-control.service \
    || fail "srv-control.service is not active"
systemctl is-active --quiet srvcc-github-agent.timer \
    || fail "srvcc-github-agent.timer is not active"

python3 - "$EXPECTED_VERSION" <<'PY'
import json
import sys
import urllib.request

expected = sys.argv[1]
with urllib.request.urlopen(
    "http://127.0.0.1:8876/api/v1/health",
    timeout=10,
) as response:
    payload = json.load(response)

if payload.get("ok") is not True:
    raise SystemExit(f"health failed: {payload!r}")
release = payload.get("data", {}).get("release", {})
if release.get("version") != expected:
    raise SystemExit(f"unexpected release metadata: {release!r}")
print(json.dumps(release, ensure_ascii=False))
PY

runuser -u postgres -- psql -v ON_ERROR_STOP=1 -d srv_control -Atc \
    "SELECT 'alembic=' || version_num FROM alembic_version;"
runuser -u postgres -- psql -v ON_ERROR_STOP=1 -d srv_control -Atc \
    "SELECT 'tables=' || count(*) FROM information_schema.tables WHERE table_schema='public';"
runuser -u postgres -- psql -v ON_ERROR_STOP=1 -d srv_control -Atc \
    "SELECT 'baseline_settings=' || count(*) FROM settings WHERE key LIKE 'control_center.%';"

server_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
server_ip="${server_ip:-127.0.0.1}"
web_port="$(awk '/^[[:space:]]*listen [0-9]+ default_server;/{print $2; exit}' /etc/nginx/sites-available/srv-control 2>/dev/null || true)"
web_port="${web_port:-80}"

if [[ "$web_port" == "80" ]]; then
    access_url="http://${server_ip}/"
else
    access_url="http://${server_ip}:${web_port}/"
fi

cat <<EOF

============================================================
SRV CONTROL CENTER CLEAN REINSTALL: PASS
release=${EXPECTED_VERSION}
url=${access_url}
github_source=${REPO_URL}
update_mode=automatic
update_interval_minutes=${UPDATE_INTERVAL_MINUTES}
updater_timer=srvcc-github-agent.timer
database=srv_control (fresh)
============================================================
EOF
