#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Запустите от root.'; exit 1; }
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="$ROOT_DIR/install/uninstall-base-1.0.7.sh"
[[ -f "$BASE" ]] || { echo 'Отсутствует uninstall-base-1.0.7.sh' >&2; exit 1; }
KEEP_DATA=false
[[ "${1:-}" == "--keep-data" ]] && KEEP_DATA=true
SYSTEM=/var/lib/control-center-system

module_active(){
  local file="$1" kind="$2"
  [[ -s "$file" ]] || return 1
  python3 - "$file" "$kind" <<'PY'
import json,sys
try:j=json.load(open(sys.argv[1]))
except Exception:raise SystemExit(1)
kind=sys.argv[2]
if kind=='domain':ok=bool(j.get('managed') and j.get('state')=='active')
else:ok=bool(j.get('installed'))
raise SystemExit(0 if ok else 1)
PY
}

DOMAIN=false;DNS=false;STORAGE=false
module_active "$SYSTEM/modules/samba.json" domain && DOMAIN=true || true
module_active "$SYSTEM/modules/dns.json" service && DNS=true || true
module_active "$SYSTEM/modules/storage.json" service && STORAGE=true || true

if ! $KEEP_DATA && { $DOMAIN || $DNS || $STORAGE; }; then
  echo 'Полное удаление Control Center заблокировано: установлены управляемые серверные службы.' >&2
  $DOMAIN && echo ' - Домен: сначала удалите в Домен → Удаление Домена (с recovery + cleanup-audit).' >&2
  $DNS && echo ' - DNS: сначала удалите DNS через Маркет (если он не является зависимостью Домена).' >&2
  $STORAGE && echo ' - Сетевое хранилище: сначала удалите службу через Маркет; пользовательские файлы сохраняются.' >&2
  echo 'После штатного удаления служб повторите uninstall. Для сохранения ролей/метаданных используйте --keep-data.' >&2
  exit 3
fi

units=(
  control-center-authd.service
  control-center-samba-apply.path control-center-samba-apply.service
  control-center-domain-destroy.path control-center-domain-destroy.service
  control-center-dns-apply.path control-center-dns-apply.service
  control-center-storage-apply.path control-center-storage-apply.service
  control-center-dhcp-reservations-apply.path control-center-dhcp-reservations-apply.service
  control-center-hostname-apply.path control-center-hostname-apply.service
  control-center-update-now.path
)
for u in "${units[@]}";do systemctl disable --now "$u" >/dev/null 2>&1 || systemctl stop "$u" >/dev/null 2>&1 || true;done
for u in "${units[@]}";do rm -f "/etc/systemd/system/$u";done

rm -f \
  /usr/local/sbin/control-center-authd \
  /usr/local/sbin/control-center-samba-apply \
  /usr/local/sbin/control-center-samba-apply-core \
  /usr/local/sbin/control-center-domain-pre \
  /usr/local/sbin/control-center-domain-post \
  /usr/local/sbin/control-center-domain-restore-prestate \
  /usr/local/sbin/control-center-domain-orchestrate \
  /usr/local/sbin/control-center-domain-destroy \
  /usr/local/sbin/control-center-samba-approve \
  /usr/local/sbin/control-center-samba-package-guard \
  /usr/local/sbin/control-center-dns-apply \
  /usr/local/sbin/control-center-storage-apply \
  /usr/local/sbin/control-center-dhcp-reservations-apply \
  /usr/local/sbin/control-center-web-run
rm -f /run/control-center/samba-provision.json /run/control-center/domain-remove.json /run/control-center-root/samba-approval.json /run/control-center-root/samba-auth-* /run/control-center-root/samba-packages-before.tsv /run/control-center-root/samba-time-services-before.tsv /run/control-center-auth/auth.sock 2>/dev/null || true
rm -f /etc/tmpfiles.d/control-center.conf
rm -rf /usr/local/lib/control-center

if ! $KEEP_DATA; then
  rm -f /etc/dnsmasq.d/control-center-dhcp-reservations.conf
  rm -f /etc/pam.d/control-center-web
  # A bootstrap controladmin account is deliberately preserved rather than
  # silently deleting a human credential that may have been reused/changed.
fi
systemctl daemon-reload

# --keep-data removes the portal/runtime but does not destroy Domain, DNS,
# Storage, their data, recovery backups or PostgreSQL application state.
bash "$BASE" "$@"
