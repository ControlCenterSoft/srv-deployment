#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Запустите от root.'; exit 1; }
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="$ROOT_DIR/install/uninstall-base-1.0.7.sh"
[[ -f "$BASE" ]] || { echo 'Отсутствует uninstall-base-1.0.7.sh' >&2; exit 1; }
KEEP_DATA=false
[[ "${1:-}" == "--keep-data" ]] && KEEP_DATA=true
SAMBA_STATE=/var/lib/control-center-system/modules/samba.json
SAMBA_ACTIVE=false
if [[ -s "$SAMBA_STATE" ]]; then
  if python3 - "$SAMBA_STATE" <<'PY'
import json,sys
try:j=json.load(open(sys.argv[1]))
except Exception:raise SystemExit(1)
raise SystemExit(0 if j.get('managed') and j.get('state')=='active' else 1)
PY
  then SAMBA_ACTIVE=true; fi
fi
if $SAMBA_ACTIVE && ! $KEEP_DATA; then
  echo 'Samba AD-DC активен и управляется Control Center.' >&2
  echo 'Обычное удаление с очисткой application data заблокировано, чтобы не потерять метаданные управления доменом.' >&2
  echo 'Используйте --keep-data. Samba, /etc/samba, /var/lib/samba, SYSVOL и доменная база не удаляются.' >&2
  exit 3
fi

systemctl disable --now control-center-update-now.path >/dev/null 2>&1 || true
systemctl disable --now control-center-samba-apply.path >/dev/null 2>&1 || true
systemctl stop control-center-samba-apply.service >/dev/null 2>&1 || true
rm -f /etc/systemd/system/control-center-update-now.path /var/lib/control-center/update-now
rm -f /etc/systemd/system/control-center-samba-apply.path /etc/systemd/system/control-center-samba-apply.service
rm -f /usr/local/sbin/control-center-samba-apply /usr/local/sbin/control-center-samba-approve
rm -f /run/control-center/samba-provision.json /run/control-center-root/samba-approval.json /run/control-center-root/samba-auth-* 2>/dev/null || true
rm -f /etc/tmpfiles.d/control-center.conf
rm -f /usr/local/sbin/control-center-web-run
rm -rf /usr/local/lib/control-center
if ! $KEEP_DATA; then rm -rf /etc/control-center/tls; fi
systemctl daemon-reload

# The AD domain is deliberately never removed here. Domain destruction is a
# separate high-risk lifecycle operation and is not part of Control Center 1.0.11.
bash "$BASE" "$@"
