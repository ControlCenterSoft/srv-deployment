#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Запустите от root: sudo bash install/install.sh'; exit 1; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="$ROOT_DIR/install/install-base-1.0.7.sh"
BASE_UPDATER="$ROOT_DIR/update/control-center-update-base-1.0.7"
BASE_OS_UPDATER="$ROOT_DIR/update/control-center-os-update-base-1.0.8"
BASE_MARKET="$ROOT_DIR/market/control-center-market-apply-base-1.0.8"
TMP="$(mktemp /tmp/control-center-install-1.0.8.XXXXXX)"
POLICY=/usr/sbin/policy-rc.d
POLICY_BACKUP="/run/control-center-policy-rc.d.install.$$"
POLICY_HAD=0
POLICY_ACTIVE=0
APT_LOCK=/run/control-center-apt.lock
APT_RESILIENCE=/etc/apt/apt.conf.d/90-control-center-resilience

cleanup(){ rm -f "$TMP"; if [[ "$POLICY_ACTIVE" == 1 ]]; then rm -f "$POLICY"; if [[ "$POLICY_HAD" == 1 && ( -e "$POLICY_BACKUP" || -L "$POLICY_BACKUP" ) ]]; then cp -a "$POLICY_BACKUP" "$POLICY"; fi; rm -f "$POLICY_BACKUP"; POLICY_ACTIVE=0; fi; }
trap cleanup EXIT
prepare_policy(){ [[ "$POLICY_ACTIVE" == 0 ]] || return 0; if [[ -e "$POLICY" || -L "$POLICY" ]]; then cp -a "$POLICY" "$POLICY_BACKUP"; rm -f "$POLICY"; POLICY_HAD=1; cat >"$POLICY" <<EOF
#!/bin/sh
if [ "\${1:-}" = "dnsmasq" ]; then exit 101; fi
exec "$POLICY_BACKUP" "\$@"
EOF
else POLICY_HAD=0; cat >"$POLICY" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "dnsmasq" ]; then exit 101; fi
exit 0
EOF
fi; chmod 0755 "$POLICY"; POLICY_ACTIVE=1; }
restore_policy(){ [[ "$POLICY_ACTIVE" == 1 ]] || return 0; rm -f "$POLICY"; if [[ "$POLICY_HAD" == 1 && ( -e "$POLICY_BACKUP" || -L "$POLICY_BACKUP" ) ]]; then cp -a "$POLICY_BACKUP" "$POLICY"; fi; rm -f "$POLICY_BACKUP"; POLICY_ACTIVE=0; }
prepare_apt_resilience(){
  cat >"$APT_RESILIENCE" <<'APT'
Acquire::Retries "3";
Acquire::http::Timeout "15";
Acquire::https::Timeout "15";
Acquire::ftp::Timeout "15";
Acquire::Queue-Mode "access";
DPkg::Lock::Timeout "900";
APT::Get::Assume-Yes "true";
APT
  chmod 0644 "$APT_RESILIENCE"
}
repair_package_database(){ install -d -o root -g root -m 0700 /var/lib/control-center-root; local log=/var/lib/control-center-root/upgrade-preflight-1.0.8.log; exec 7>"$APT_LOCK"; flock -w 900 7 || { echo 'Менеджер пакетов занят более 15 минут.' >&2; return 75; }; export DEBIAN_FRONTEND=noninteractive; prepare_apt_resilience; prepare_policy; { echo "[$(date -Is)] Control Center 1.0.8 build 20260819.2 package preflight"; dpkg --audit || true; dpkg --configure -a || true; apt-get -f install -y; dpkg --configure -a; dpkg --audit || true; } 2>&1 | tee -a "$log"; restore_policy; flock -u 7; }

[[ -f "$BASE" ]] || { echo 'Отсутствует install/install-base-1.0.7.sh' >&2; exit 1; }
[[ -f "$BASE_UPDATER" ]] || { echo 'Отсутствует update/control-center-update-base-1.0.7' >&2; exit 1; }
[[ -f "$BASE_OS_UPDATER" ]] || { echo 'Отсутствует update/control-center-os-update-base-1.0.8' >&2; exit 1; }
[[ -f "$BASE_MARKET" ]] || { echo 'Отсутствует market/control-center-market-apply-base-1.0.8' >&2; exit 1; }
repair_package_database
install -d -m 0755 /usr/local/lib/control-center
install -m 0755 "$BASE_UPDATER" /usr/local/lib/control-center/control-center-update-base-1.0.7
install -m 0755 "$BASE_OS_UPDATER" /usr/local/lib/control-center/control-center-os-update-base-1.0.8
install -m 0755 "$BASE_MARKET" /usr/local/lib/control-center/control-center-market-apply-base-1.0.8
python3 - "$BASE" "$TMP" <<'PY'
from pathlib import Path
import sys
src,dst=map(Path,sys.argv[1:]);text=src.read_text();old_root='ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"';new_root='ROOT_DIR="${CONTROL_CENTER_RELEASE_ROOT:?}"'
if old_root not in text: raise SystemExit('Base installer ROOT_DIR marker not found')
text=text.replace(old_root,new_root,1)
if 'VERSION=1.0.7' not in text or 'BUILD=20260818.2' not in text: raise SystemExit('Base installer version/build markers not found')
text=text.replace('VERSION=1.0.7','VERSION=1.0.8',1).replace('BUILD=20260818.2','BUILD=20260819.2',1);dst.write_text(text)
PY
chmod 0755 "$TMP"
CONTROL_CENTER_RELEASE_ROOT="$ROOT_DIR" bash "$TMP" "$@"
cat >/etc/systemd/system/control-center-update-now.path <<'UNIT'
[Unit]
Description=Control Center manual update request watcher
[Path]
PathExists=/var/lib/control-center/update-now
Unit=control-center-update.service
[Install]
WantedBy=multi-user.target
UNIT
rm -f /var/lib/control-center/update-now
systemctl daemon-reload
systemctl enable --now control-center-update-now.path
echo 'Control Center 1.0.8 build 20260819.2: legacy updater compatibility and package repair enabled.'
