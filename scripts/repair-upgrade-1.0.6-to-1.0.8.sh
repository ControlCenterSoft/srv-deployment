#!/usr/bin/env bash
set -Eeuo pipefail

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Запустите от root.' >&2; exit 1; }

TARGET=1.0.8
EXPECTED_BUILD=20260819.2
STATE=/var/lib/control-center
SYSTEM_STATE=/var/lib/control-center-system
ROOT_STATE=/var/lib/control-center-root
SETTINGS="$STATE/update-settings.json"
STATUS="$SYSTEM_STATE/update-status.json"
MARKET_STATUS="$SYSTEM_STATE/market-status.json"
MARKER="$SYSTEM_STATE/dhcp-recovery-legacy.json"
UPDATER=/usr/local/sbin/control-center-update
STAMP="$(date +%Y%m%dT%H%M%S)"
BACKUP="$ROOT_STATE/manual-repair-$STAMP"

install -d -o root -g root -m 0700 "$ROOT_STATE" "$BACKUP"
install -d -o root -g control-center -m 0750 "$SYSTEM_STATE"

CURRENT="$(cat /opt/control-center/VERSION 2>/dev/null || echo unknown)"
echo "Control Center recovery: current=$CURRENT target=$TARGET build=$EXPECTED_BUILD"

for f in "$SETTINGS" "$STATUS" "$MARKET_STATUS" /etc/dnsmasq.conf; do
  [[ -e "$f" || -L "$f" ]] && cp -a "$f" "$BACKUP/" 2>/dev/null || true
done
[[ -d /etc/dnsmasq.d ]] && cp -a /etc/dnsmasq.d "$BACKUP/dnsmasq.d" || true
[[ -d "$SYSTEM_STATE/modules" ]] && cp -a "$SYSTEM_STATE/modules" "$BACKUP/modules" || true
journalctl -u control-center-update.service -n 300 --no-pager >"$BACKUP/update-journal.txt" 2>&1 || true
journalctl -u control-center-market-apply.service -n 300 --no-pager >"$BACKUP/market-journal.txt" 2>&1 || true
dpkg --audit >"$BACKUP/dpkg-audit.txt" 2>&1 || true
dpkg-query -W -f='${Package}\t${Status}\t${Version}\n' dnsmasq dnsmasq-base >"$BACKUP/dnsmasq-packages.txt" 2>&1 || true

has_external_dnsmasq_config(){
  local f
  for f in /etc/dnsmasq.conf /etc/dnsmasq.d/*; do
    [[ -f "$f" ]] || continue
    [[ "$f" == /etc/dnsmasq.d/control-center-dhcp.conf ]] && continue
    if grep -Eq '^[[:space:]]*[^#[:space:]]' "$f"; then
      echo "Найдена внешняя конфигурация dnsmasq: $f"
      return 0
    fi
  done
  return 1
}

# The screenshots for the legacy 1.0.6 failure show apt code 100 followed by
# dnsmasq being seen as "outside Control Center". Mark it as recoverable only
# when there is no active external dnsmasq configuration and no module state.
if [[ "$CURRENT" == 1.0.6 ]] \
   && dpkg-query -W -f='${Status}' dnsmasq 2>/dev/null | grep -q 'install ok installed' \
   && [[ ! -f "$SYSTEM_STATE/modules/dhcp.json" ]] \
   && ! has_external_dnsmasq_config; then
  python3 - "$MARKER" "$CURRENT" <<'PY'
import json,sys,time,os,tempfile
path,current=sys.argv[1:]
data={
  'source':'manual-repair-script',
  'legacy_version':current,
  'reason':'legacy Market apt code 100 left dnsmasq installed before module state was committed',
  'created_at':int(time.time()),
}
fd,tmp=tempfile.mkstemp(prefix='.dhcp-recovery.',dir=os.path.dirname(path))
with os.fdopen(fd,'w') as f:
    json.dump(data,f,ensure_ascii=False,indent=2);f.write('\n');f.flush();os.fsync(f.fileno())
os.replace(tmp,path)
PY
  chown root:control-center "$MARKER"
  chmod 0640 "$MARKER"
  echo 'Подготовлен безопасный marker восстановления DHCP.'
else
  echo 'DHCP recovery marker не создавался: либо пакет отсутствует/уже зарегистрирован, либо есть внешняя конфигурация.'
fi

[[ -x "$UPDATER" ]] || { echo "Не найден updater: $UPDATER" >&2; exit 1; }

ORIGINAL_SETTINGS="$(cat "$SETTINGS" 2>/dev/null || printf '%s' '{"automatic_updates":true,"interval_minutes":60,"channel":"production"}')"
python3 - "$SETTINGS" <<'PY'
import json,sys,os,tempfile
path=sys.argv[1]
try:data=json.load(open(path))
except Exception:data={}
data['automatic_updates']=True
data['interval_minutes']=5
data['channel']='production'
os.makedirs(os.path.dirname(path),exist_ok=True)
fd,tmp=tempfile.mkstemp(prefix='.update-settings.',dir=os.path.dirname(path))
with os.fdopen(fd,'w') as f:
    json.dump(data,f,ensure_ascii=False,indent=2);f.write('\n');f.flush();os.fsync(f.fileno())
os.replace(tmp,path)
PY
chown control-center:control-center "$SETTINGS" 2>/dev/null || true
chmod 0640 "$SETTINGS" 2>/dev/null || true

python3 - "$STATUS" <<'PY'
import json,sys,os,time,tempfile
path=sys.argv[1]
os.makedirs(os.path.dirname(path),exist_ok=True)
data={'last_check':0,'result':'repair','message':'Ручное восстановление production update запущено','timestamp':int(time.time())}
fd,tmp=tempfile.mkstemp(prefix='.update-status.',dir=os.path.dirname(path))
with os.fdopen(fd,'w') as f:
    json.dump(data,f,ensure_ascii=False,indent=2);f.write('\n');f.flush();os.fsync(f.fileno())
os.replace(tmp,path)
PY
chown root:control-center "$STATUS"
chmod 0640 "$STATUS"

set +e
"$UPDATER"
RC=$?
set -e

if [[ "$RC" != 0 ]]; then
  printf '%s\n' "$ORIGINAL_SETTINGS" >"$SETTINGS"
  chown control-center:control-center "$SETTINGS" 2>/dev/null || true
  chmod 0640 "$SETTINGS" 2>/dev/null || true
  echo "Обновление снова завершилось ошибкой (код $RC). Диагностика сохранена: $BACKUP" >&2
  journalctl -u control-center-update.service -n 120 --no-pager || true
  exit "$RC"
fi

NEW_VERSION="$(cat /opt/control-center/VERSION 2>/dev/null || echo unknown)"
NEW_BUILD="$(cat /opt/control-center/BUILD 2>/dev/null || echo unknown)"
if [[ "$NEW_VERSION" != "$TARGET" || "$NEW_BUILD" != "$EXPECTED_BUILD" ]]; then
  echo "Updater завершился без ошибки, но установлена неожиданная версия: $NEW_VERSION build $NEW_BUILD" >&2
  exit 2
fi

# Restore the user's update preferences through the current API when possible.
PORT="$(sed -n 's/^CONTROL_CENTER_PORT=\([0-9][0-9]*\)$/\1/p' /etc/control-center/web.env 2>/dev/null | head -n1)"
PORT="${PORT:-8080}"
python3 - "$ORIGINAL_SETTINGS" >"$BACKUP/original-update-settings.json" <<'PY'
import json,sys
try:data=json.loads(sys.argv[1])
except Exception:data={'automatic_updates':True,'interval_minutes':60,'channel':'production'}
print(json.dumps({
 'automatic_updates':bool(data.get('automatic_updates',True)),
 'interval_minutes':int(data.get('interval_minutes',60)),
 'channel':'production'
}))
PY
if curl -fsS -X POST -H 'Content-Type: application/json' \
  --data-binary @"$BACKUP/original-update-settings.json" \
  "http://127.0.0.1:${PORT}/api/settings/update" >/dev/null 2>&1; then
  echo 'Исходные настройки автоматических обновлений восстановлены через API.'
fi

# Recover the DHCP package only when the explicit legacy marker was created.
if [[ -f "$MARKER" ]]; then
  python3 - "$STATE/market-pending.json" <<'PY'
import json,sys,time,os,tempfile
path=sys.argv[1]
os.makedirs(os.path.dirname(path),exist_ok=True)
data={'module':'dhcp','action':'install','requested_at':int(time.time()),'request_id':f'legacy-recovery-{int(time.time()*1000)}'}
fd,tmp=tempfile.mkstemp(prefix='.market-pending.',dir=os.path.dirname(path))
with os.fdopen(fd,'w') as f:
    json.dump(data,f,ensure_ascii=False,indent=2);f.write('\n');f.flush();os.fsync(f.fileno())
os.replace(tmp,path)
PY
  chown control-center:control-center "$STATE/market-pending.json" 2>/dev/null || true
  chmod 0640 "$STATE/market-pending.json" 2>/dev/null || true
  systemctl start control-center-market-apply.service
fi

curl -fsS "http://127.0.0.1:${PORT}/api/health" | python3 -m json.tool
printf '\nВосстановление завершено. Установлен Control Center %s build %s.\n' "$NEW_VERSION" "$NEW_BUILD"
printf 'Диагностическая копия до изменений: %s\n' "$BACKUP"
