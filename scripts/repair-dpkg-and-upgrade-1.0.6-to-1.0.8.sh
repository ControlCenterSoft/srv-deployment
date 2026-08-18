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
ROOT_STATE=/var/lib/control-center-root
RECOVERY_SWAP="$ROOT_STATE/recovery.swap"
SWAP_CREATED=0

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
install -d -o root -g root -m 0700 "$ROOT_STATE"

printf '\nПамять до восстановления:\n'
free -h || true
swapon --show || true
printf '\nПоследние сообщения ядра об OOM/SIGKILL (если есть):\n'
journalctl -k --since '-2 hours' --no-pager 2>/dev/null | grep -Ei 'out of memory|oom-kill|killed process|memory cgroup out of memory' | tail -n 30 || true
printf '\nСостояние dpkg до восстановления:\n'
dpkg --audit || true

# A bare "Killed" from apt/dpkg normally means SIGKILL. On small VPS the most
# common source is the kernel/cgroup OOM killer. Ensure enough temporary virtual
# memory for package configuration and the following PostgreSQL installation.
MEM_AVAILABLE_KB="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
SWAP_FREE_KB="$(awk '/^SwapFree:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
MEM_AVAILABLE_KB="${MEM_AVAILABLE_KB:-0}"
SWAP_FREE_KB="${SWAP_FREE_KB:-0}"
TOTAL_RECOVERY_KB=$((MEM_AVAILABLE_KB + SWAP_FREE_KB))
MIN_RECOVERY_KB=$((1024 * 1024))

if (( TOTAL_RECOVERY_KB < MIN_RECOVERY_KB )); then
  if swapon --show --noheadings --raw --output NAME 2>/dev/null | grep -Fxq "$RECOVERY_SWAP"; then
    echo "Recovery swap уже активен: $RECOVERY_SWAP"
  else
    AVAILABLE_MB="$(df -Pm "$ROOT_STATE" | awk 'NR==2 {print $4}')"
    AVAILABLE_MB="${AVAILABLE_MB:-0}"
    if (( AVAILABLE_MB >= 2300 )); then SWAP_MB=2048
    elif (( AVAILABLE_MB >= 1300 )); then SWAP_MB=1024
    elif (( AVAILABLE_MB >= 700 )); then SWAP_MB=512
    else
      echo "Недостаточно RAM/Swap и свободного диска для безопасного восстановления." >&2
      echo "MemAvailable+SwapFree: $((TOTAL_RECOVERY_KB/1024)) MiB; свободно на диске: ${AVAILABLE_MB} MiB." >&2
      exit 12
    fi
    echo "Создаю временный recovery swap ${SWAP_MB} MiB: $RECOVERY_SWAP"
    rm -f "$RECOVERY_SWAP"
    if ! fallocate -l "${SWAP_MB}M" "$RECOVERY_SWAP" 2>/dev/null; then
      dd if=/dev/zero of="$RECOVERY_SWAP" bs=1M count="$SWAP_MB" status=progress
    fi
    chmod 0600 "$RECOVERY_SWAP"
    mkswap -f "$RECOVERY_SWAP" >/dev/null
    if ! swapon "$RECOVERY_SWAP"; then
      rm -f "$RECOVERY_SWAP"
      echo 'Не удалось включить swap. На этом VPS может быть запрещён swapon; потребуется увеличить RAM/Swap у провайдера.' >&2
      exit 13
    fi
    SWAP_CREATED=1
    echo 'Recovery swap включён и останется активным до перезагрузки; в /etc/fstab он не добавляется.'
  fi
fi

printf '\nПамять перед APT recovery:\n'
free -h || true
swapon --show || true

exec 8>"$APT_LOCK"
flock -w 900 8 || { echo 'Не удалось получить внутреннюю блокировку Control Center за 900 секунд.' >&2; exit 75; }

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

# Let APT wait for the real dpkg frontend lock. It will configure unpacked
# dependencies such as cloud-init before ubuntu-server-minimal. Existing local
# configuration files are retained with --force-confold.
echo 'Завершаю незавершённую пакетную транзакцию...'
apt-get \
  -o DPkg::Lock::Timeout=300 \
  -o Dpkg::Options::='--force-confold' \
  -f install -y

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

printf '\nПамять после восстановления:\n'
free -h || true
swapon --show || true
if [[ "$SWAP_CREATED" == 1 ]]; then
  echo "Временный swap $RECOVERY_SWAP оставлен активным до перезагрузки, чтобы PostgreSQL и post-install проверки не попали под OOM."
  echo 'После успешной проверки сервера решим, нужен ли постоянный swap для этой конфигурации VPS.'
fi
