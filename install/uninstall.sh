#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Запустите от root.'; exit 1; }
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="$ROOT_DIR/install/uninstall-base-1.0.7.sh"
[[ -f "$BASE" ]] || { echo 'Отсутствует uninstall-base-1.0.7.sh' >&2; exit 1; }
KEEP_DATA=false
[[ "${1:-}" == "--keep-data" ]] && KEEP_DATA=true
systemctl disable --now control-center-update-now.path >/dev/null 2>&1 || true
rm -f /etc/systemd/system/control-center-update-now.path /var/lib/control-center/update-now
rm -f /usr/local/sbin/control-center-web-run
rm -rf /usr/local/lib/control-center
if ! $KEEP_DATA; then rm -rf /etc/control-center/tls; fi
systemctl daemon-reload
bash "$BASE" "$@"
