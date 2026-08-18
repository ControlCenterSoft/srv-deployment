#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Запустите от root: sudo bash install/install.sh'; exit 1; }
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="$ROOT_DIR/install/install-base-1.0.7.sh"
BASE_UPDATER="$ROOT_DIR/update/control-center-update-base-1.0.7"
TMP="$(mktemp /tmp/control-center-install-1.0.8.XXXXXX)"
trap 'rm -f "$TMP"' EXIT
[[ -f "$BASE" ]] || { echo 'Отсутствует install/install-base-1.0.7.sh' >&2; exit 1; }
[[ -f "$BASE_UPDATER" ]] || { echo 'Отсутствует update/control-center-update-base-1.0.7' >&2; exit 1; }

install -d -m 0755 /usr/local/lib/control-center
install -m 0755 "$BASE_UPDATER" /usr/local/lib/control-center/control-center-update-base-1.0.7

python3 - "$BASE" "$TMP" <<'PY'
from pathlib import Path
import sys
src,dst=map(Path,sys.argv[1:])
text=src.read_text()
old_root='ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"'
new_root='ROOT_DIR="${CONTROL_CENTER_RELEASE_ROOT:?}"'
if old_root not in text:
    raise SystemExit('Base installer ROOT_DIR marker not found')
text=text.replace(old_root,new_root,1)
if 'VERSION=1.0.7' not in text or 'BUILD=20260818.2' not in text:
    raise SystemExit('Base installer version/build markers not found')
text=text.replace('VERSION=1.0.7','VERSION=1.0.8',1)
text=text.replace('BUILD=20260818.2','BUILD=20260819.1',1)
dst.write_text(text)
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

echo 'Control Center 1.0.8: persistent Market statuses, DHCP install recovery and manual update trigger enabled.'
