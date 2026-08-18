#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Запустите от root.'; exit 1; }
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="$ROOT_DIR/install/uninstall-base-1.0.7.sh"
[[ -f "$BASE" ]] || { echo 'Отсутствует uninstall-base-1.0.7.sh' >&2; exit 1; }
systemctl disable --now control-center-update-now.path >/dev/null 2>&1 || true
rm -f /etc/systemd/system/control-center-update-now.path /var/lib/control-center/update-now
rm -rf /usr/local/lib/control-center
systemctl daemon-reload
bash "$BASE" "$@"
