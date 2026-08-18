#!/usr/bin/env bash
set -Eeuo pipefail

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Запустите от root.' >&2; exit 1; }

APT_LOCK=/run/control-center-apt.lock
POLICY=/usr/sbin/policy-rc.d
POLICY_BACKUP="/run/control-center-policy-rc.d.repair.$$"
POLICY_HAD=0
POLICY_ACTIVE=0
TMP="$(mktemp /tmp/control-center-repair-upgrade.XXXXXX)"
UPGRADE_URL='https://raw.githubusercontent.com/filosoff31/srv-deployment/release/1.0.8/scripts/repair-upgrade-1.0.6-to-1.0.8.sh'

restore_policy(){
  [[ "$POLICY_ACTIVE" == 1 ]] || return 0
  rm -f "$POLICY"
  if [[ "$POLICY_HAD" == 1 && ( -e "$POLICY_BACKUP" || -L "$POLICY_BACKUP" ) ]]; then
    cp -a "$POLICY_BACKUP" "$POLICY"
  fi
  rm -f "$POLICY_BACKUP"
  POLICY_ACTIVE=0
}
cleanup(){ restore_policy || true; rm -f "$TMP"; }
trap cleanup EXIT

printf '=== Control Center package recovery ===\n'
printf 'Текущая версия: %s\n' "$(cat /opt/control-center/VERSION 2>/dev/null || echo unknown)"
printf '\nСостояние dpkg до восстановления:\n'
dpkg --audit || true

exec 8>"$APT_LOCK"
flock -w 900 8 || { echo 'Не удалось получить блокировку менеджера пакетов за 900 секунд.' >&2; exit 75; }

# Do not let an already unpacked dnsmasq start while dpkg/apt finishes an
# interrupted transaction. Preserve any provider/local policy-rc.d exactly.
if [[ -e "$POLICY" || -L "$POLICY" ]]; then
  cp -a "$POLICY" "$POLICY_BACKUP"
  POLICY_HAD=1
  cat >"$POLICY" <<EOF
#!/bin/sh
if [ "\${1:-}" = "dnsmasq" ]; then exit 101; fi
exec "$POLICY_BACKUP" "\$@"
EOF
else
  cat >"$POLICY" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "dnsmasq" ]; then exit 101; fi
exit 0
EOF
fi
chmod 0755 "$POLICY"
POLICY_ACTIVE=1

export DEBIAN_FRONTEND=noninteractive

# First configuration pass may fail if a dependency also needs repair; that is
# why apt-get -f install follows it. --force-confold keeps existing local
# configuration files instead of replacing them during unattended recovery.
set +e
dpkg --force-confold --configure -a
FIRST_RC=$?
set -e
if [[ "$FIRST_RC" != 0 ]]; then
  echo "Первый dpkg --configure -a завершился кодом $FIRST_RC; выполняю dependency repair через apt-get -f install."
fi

apt-get -o Dpkg::Options::='--force-confold' -f install -y
dpkg --force-confold --configure -a

AUDIT="$(dpkg --audit 2>&1 || true)"
if [[ -n "${AUDIT//[[:space:]]/}" ]]; then
  printf '\nПосле восстановления dpkg всё ещё сообщает незавершённые пакеты:\n%s\n' "$AUDIT" >&2
  echo 'Обновление Control Center не запускаю, чтобы не усугублять состояние системы.' >&2
  exit 2
fi

printf '\ndpkg восстановлен: незавершённых пакетов нет.\n'
restore_policy
flock -u 8

curl -fsSL "$UPGRADE_URL" -o "$TMP"
chmod 0700 "$TMP"
echo 'Запускаю штатное восстановление Control Center 1.0.6 -> 1.0.8...'
bash "$TMP"
