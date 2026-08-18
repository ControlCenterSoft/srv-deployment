#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
STATE_DIR="/var/lib/srv-control"
APP_USER="srv-control"
APP_GROUP="srv-control"
PROFILE="$REPO_ROOT/installer/install-profile.json"

fail() {
    printf 'SYSTEM ADMIN INSTALL FAIL: %s\n' "$*" >&2
    exit 1
}

[[ "$(id -u)" -eq 0 ]] || fail "must run as root"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"
[[ -s "$PROFILE" ]] || fail "install profile is missing"

system_path="$(python3 - "$PROFILE" <<'PY'
import json,pathlib,sys
profile=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
value=profile.get('system_baseline')
if not isinstance(value,str) or not value:
    raise SystemExit('system_baseline missing')
print(value)
PY
)"
SYSTEM_DIR="$REPO_ROOT/$system_path"

for executable in \
    srv-control-system-agent \
    srv-control-os-update \
    srv-control-adguard-monitor \
    srv-control-backup \
    srv-control-os-auto-update
do
    [[ -x "$SYSTEM_DIR/$executable" ]] || fail "system executable missing: $executable"
done
[[ -x "$SYSTEM_DIR/install-auth.sh" ]] || fail "authentication integration installer missing"

install -d -m 0750 -o "$APP_USER" -g "$APP_GROUP" \
    "$STATE_DIR" \
    "$STATE_DIR/system-actions" \
    "$STATE_DIR/system-results" \
    "$STATE_DIR/backups"
install -d -m 0755 /usr/local/libexec

for executable in \
    srv-control-system-agent \
    srv-control-os-update \
    srv-control-adguard-monitor \
    srv-control-backup \
    srv-control-os-auto-update
do
    install -m 0755 -o root -g root \
        "$SYSTEM_DIR/$executable" \
        "/usr/local/libexec/$executable"
done

for unit in \
    srv-control-system-agent.service \
    srv-control-system-agent.path \
    srv-control-os-update.service \
    srv-control-adguard-monitor.service \
    srv-control-adguard-monitor.timer \
    srv-control-backup.service \
    srv-control-backup.timer \
    srv-control-os-auto-update.service \
    srv-control-os-auto-update.timer
do
    [[ -s "$SYSTEM_DIR/$unit" ]] || fail "systemd payload missing: $unit"
    install -m 0644 -o root -g root \
        "$SYSTEM_DIR/$unit" \
        "/etc/systemd/system/$unit"
done

# The current application uses the 2.1.1 NoNewPrivileges-safe Minecraft bridge.
# Install its root agent and reuse the proven path/service units from the 2.1.0
# consolidated system baseline. This is safe even when Bedrock itself has not yet
# been installed on a clean host; operations then report service unavailable.
MC_AGENT="$REPO_ROOT/releases/2.1.1/system/srv-control-minecraft-agent"
if [[ -x "$MC_AGENT" ]]; then
    install -d -m 0770 -o root -g "$APP_GROUP" "$STATE_DIR/minecraft-actions"
    install -m 0755 -o root -g root "$MC_AGENT" /usr/local/libexec/srv-control-minecraft-agent
    for unit in srv-control-minecraft-agent.service srv-control-minecraft-agent.path; do
        [[ -s "$SYSTEM_DIR/$unit" ]] || fail "Minecraft agent unit missing: $unit"
        install -m 0644 -o root -g root "$SYSTEM_DIR/$unit" "/etc/systemd/system/$unit"
    done
fi

if [[ ! -s "$STATE_DIR/session.key" ]]; then
    python3 - "$STATE_DIR/session.key" <<'PY'
import os
import pathlib
import sys
path=pathlib.Path(sys.argv[1])
path.write_text(os.urandom(32).hex()+"\n",encoding="ascii")
PY
    chown "$APP_USER:$APP_GROUP" "$STATE_DIR/session.key"
    chmod 0600 "$STATE_DIR/session.key"
fi

python3 - "$STATE_DIR" <<'PY'
import json
import os
import pathlib
import sys
state=pathlib.Path(sys.argv[1])
def create(name,payload,mode=0o644):
    path=state/name
    if path.exists():
        return
    path.write_text(json.dumps(payload,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    os.chmod(path,mode)
create("login-guard.json", {"schema_version":2,"entries":{}}, 0o640)
create("os-update-config.json", {"schema_version":1,"mode":"manual","interval_hours":24})
create("backup-config.json", {"schema_version":1,"scheduled":False,"daily_time":"03:00","backup_before_update":True})
PY
chown "$APP_USER:$APP_GROUP" "$STATE_DIR/login-guard.json"
chown "$APP_USER:$APP_GROUP" "$STATE_DIR/os-update-config.json" "$STATE_DIR/backup-config.json"

rm -f "$STATE_DIR/auth.json" "$STATE_DIR/admin-bootstrap.txt"

systemctl daemon-reload
systemctl enable --now srv-control-system-agent.path
systemctl enable --now srv-control-adguard-monitor.timer
systemctl start srv-control-adguard-monitor.service || true
systemctl disable --now srv-control-backup.timer >/dev/null 2>&1 || true
systemctl disable --now srv-control-os-auto-update.timer >/dev/null 2>&1 || true
if [[ -x /usr/local/libexec/srv-control-minecraft-agent ]]; then
    systemctl enable --now srv-control-minecraft-agent.path
fi

bash "$SYSTEM_DIR/install-auth.sh"

printf 'SYSTEM ADMIN INSTALL PASS: source=%s\n' "$system_path"
