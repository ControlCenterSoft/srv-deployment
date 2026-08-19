#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Запустите от root: sudo bash install/install.sh'; exit 1; }
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="$ROOT_DIR/install/install-base-1.0.8.sh"
TMP="$(mktemp /tmp/control-center-install-1.0.11.XXXXXX)"
OLD_WEB_ENV="$(cat /etc/control-center/web.env 2>/dev/null || true)"
trap 'rm -f "$TMP"' EXIT
[[ -f "$BASE" ]] || { echo 'Отсутствует install/install-base-1.0.8.sh' >&2; exit 1; }

python3 - "$BASE" "$TMP" <<'PY'
from pathlib import Path
import sys
src,dst=map(Path,sys.argv[1:]);text=src.read_text()
old_root='ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"'
if old_root not in text: raise SystemExit('Base 1.0.8 ROOT_DIR marker not found')
text=text.replace(old_root,'ROOT_DIR="${CONTROL_CENTER_RELEASE_ROOT:?}"',1)
text=text.replace('Control Center 1.0.8 build 20260819.2','Control Center 1.0.11 build 20260819.5')
text=text.replace("'VERSION=1.0.7','VERSION=1.0.8'","'VERSION=1.0.7','VERSION=1.0.11'")
text=text.replace("'BUILD=20260818.2','BUILD=20260819.2'","'BUILD=20260818.2','BUILD=20260819.5'")
text=text.replace('control-center-install-1.0.8.','control-center-install-1.0.11.')
dst.write_text(text)
PY
chmod 0755 "$TMP"
CONTROL_CENTER_RELEASE_ROOT="$ROOT_DIR" bash "$TMP" "$@"

# Portal authentication runtime. The Web process never reads /etc/shadow and
# never joins winbindd_priv: password verification is delegated over a local
# root-owned Unix socket to control-center-authd.
export DEBIAN_FRONTEND=noninteractive
exec 9>/run/control-center-apt.lock
flock -w 900 9 || { echo 'Менеджер пакетов занят.' >&2; exit 75; }
apt-get update
apt-get install -y pamtester
flock -u 9

groupadd -f control-center-admins
while IFS=: read -r user _ uid _; do
  [[ "$uid" =~ ^[0-9]+$ ]] || continue
  (( uid >= 1000 )) || continue
  groups="$(id -nG "$user" 2>/dev/null || true)"
  if grep -qwE '(sudo|wheel)' <<<"$groups"; then usermod -aG control-center-admins "$user"; fi
done </etc/passwd
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER:-root}" != root ]] && id "$SUDO_USER" >/dev/null 2>&1; then
  uid="$(id -u "$SUDO_USER")"; (( uid >= 1000 )) && usermod -aG control-center-admins "$SUDO_USER" || true
fi
cat >/etc/pam.d/control-center-web <<'PAM'
# Control Center local portal authentication.
auth    include common-auth
account include common-account
PAM
chmod 0644 /etc/pam.d/control-center-web

install -d -o root -g root -m 0755 /etc/control-center
AUTH_ENV=/etc/control-center/auth.env
if [[ ! -s "$AUTH_ENV" ]] || ! grep -Eq '^CONTROL_CENTER_SESSION_SECRET=[0-9a-f]{64}$' "$AUTH_ENV"; then
  SECRET="$(openssl rand -hex 32)"
  printf 'CONTROL_CENTER_SESSION_SECRET=%s\n' "$SECRET" >"$AUTH_ENV"
  unset SECRET
fi
chown root:control-center "$AUTH_ENV"; chmod 0640 "$AUTH_ENV"

install -m 0755 "$ROOT_DIR/system/control-center-authd" /usr/local/sbin/control-center-authd
install -m 0755 "$ROOT_DIR/system/control-center-web-run" /usr/local/sbin/control-center-web-run
install -m 0755 "$ROOT_DIR/system/control-center-web-apply" /usr/local/sbin/control-center-web-apply
install -m 0755 "$ROOT_DIR/system/control-center-hostname-apply" /usr/local/sbin/control-center-hostname-apply
install -m 0755 "$ROOT_DIR/system/control-center-samba-apply" /usr/local/sbin/control-center-samba-apply-core
install -m 0755 "$ROOT_DIR/system/control-center-domain-pre" /usr/local/sbin/control-center-domain-pre
install -m 0755 "$ROOT_DIR/system/control-center-domain-post" /usr/local/sbin/control-center-domain-post
install -m 0755 "$ROOT_DIR/system/control-center-domain-restore-prestate" /usr/local/sbin/control-center-domain-restore-prestate
install -m 0755 "$ROOT_DIR/system/control-center-domain-orchestrate" /usr/local/sbin/control-center-domain-orchestrate
install -m 0755 "$ROOT_DIR/system/control-center-domain-orchestrate" /usr/local/sbin/control-center-samba-apply
install -m 0755 "$ROOT_DIR/system/control-center-domain-destroy" /usr/local/sbin/control-center-domain-destroy
install -m 0755 "$ROOT_DIR/system/control-center-samba-approve" /usr/local/sbin/control-center-samba-approve
install -m 0755 "$ROOT_DIR/system/control-center-samba-package-guard" /usr/local/sbin/control-center-samba-package-guard
install -m 0755 "$ROOT_DIR/network/control-center-network-apply" /usr/local/sbin/control-center-network-apply
install -m 0755 "$ROOT_DIR/market/control-center-dhcp-apply" /usr/local/sbin/control-center-dhcp-apply
install -m 0755 "$ROOT_DIR/market/control-center-dns-apply" /usr/local/sbin/control-center-dns-apply
install -m 0755 "$ROOT_DIR/market/control-center-storage-apply" /usr/local/sbin/control-center-storage-apply
install -m 0755 "$ROOT_DIR/market/control-center-dhcp-reservations-apply" /usr/local/sbin/control-center-dhcp-reservations-apply

cat >/etc/tmpfiles.d/control-center.conf <<'TMPFILES'
d /run/control-center 0700 control-center control-center -
d /run/control-center-root 0700 root root -
d /run/control-center-auth 0750 root control-center -
TMPFILES
chmod 0644 /etc/tmpfiles.d/control-center.conf
systemd-tmpfiles --create /etc/tmpfiles.d/control-center.conf
rm -f /run/control-center/samba-provision.json /run/control-center/domain-remove.json /run/control-center-root/samba-approval.json /run/control-center-root/samba-auth-* /run/control-center-root/samba-packages-before.tsv /run/control-center-root/samba-time-services-before.tsv /run/control-center-auth/auth.sock 2>/dev/null || true

install -d -m 0755 /etc/dnsmasq.d
if [[ ! -e /etc/dnsmasq.d/control-center-dhcp-reservations.conf ]]; then
  printf '# Managed by Control Center DHCP reservations\n' >/etc/dnsmasq.d/control-center-dhcp-reservations.conf
fi
chmod 0644 /etc/dnsmasq.d/control-center-dhcp-reservations.conf

OLD_PORT="$(printf '%s\n' "$OLD_WEB_ENV" | sed -n 's/^CONTROL_CENTER_PORT=//p' | head -1)"
PORT="${OLD_PORT:-$(sed -n 's/^CONTROL_CENTER_PORT=//p' /etc/control-center/web.env 2>/dev/null | head -1)}"; PORT="${PORT:-8080}"
SSL="$(printf '%s\n' "$OLD_WEB_ENV" | sed -n 's/^CONTROL_CENTER_SSL=//p' | head -1)"; SSL="${SSL:-0}"
STANDARD="$(printf '%s\n' "$OLD_WEB_ENV" | sed -n 's/^CONTROL_CENTER_STANDARD_PORT=//p' | head -1)"; STANDARD="${STANDARD:-0}"
CERT=/etc/control-center/tls/server.crt
KEY=/etc/control-center/tls/server.key
cat >/etc/control-center/web.env <<EOF
CONTROL_CENTER_PORT=$PORT
CONTROL_CENTER_SSL=$SSL
CONTROL_CENTER_STANDARD_PORT=$STANDARD
CONTROL_CENTER_CERT=$CERT
CONTROL_CENTER_KEY=$KEY
EOF
chown root:root /etc/control-center/web.env; chmod 0600 /etc/control-center/web.env

cat >/etc/systemd/system/control-center-authd.service <<'UNIT'
[Unit]
Description=Control Center isolated local/domain authentication daemon
After=local-fs.target
Before=control-center.service
[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/local/sbin/control-center-authd
Restart=on-failure
RestartSec=2
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true
ReadWritePaths=/run/control-center-auth
ReadOnlyPaths=/var/lib/control-center-system /var/lib/samba /etc/pam.d /etc/passwd /etc/group /etc/shadow
[Install]
WantedBy=multi-user.target
UNIT
cat >/etc/systemd/system/control-center.service <<'UNIT'
[Unit]
Description=Control Center web interface
After=network-online.target postgresql.service control-center-authd.service
Wants=network-online.target postgresql.service control-center-authd.service
[Service]
Type=simple
User=control-center
Group=control-center
WorkingDirectory=/opt/control-center/app
Environment=PYTHONDONTWRITEBYTECODE=1
EnvironmentFile=-/etc/control-center/database.env
EnvironmentFile=-/etc/control-center/web.env
EnvironmentFile=-/etc/control-center/auth.env
ExecStart=/usr/local/sbin/control-center-web-run
Restart=on-failure
RestartSec=3
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true
ReadWritePaths=/var/lib/control-center /run/control-center
ReadOnlyPaths=/var/lib/control-center-system /var/lib/control-center-license /etc/netplan/90-control-center.yaml /etc/dnsmasq.d/control-center-dhcp.conf /etc/dnsmasq.d/control-center-dhcp-reservations.conf
InaccessiblePaths=/var/lib/control-center-root /run/control-center-root
[Install]
WantedBy=multi-user.target
UNIT
cat >/etc/systemd/system/control-center-hostname-apply.service <<'UNIT'
[Unit]
Description=Control Center hostname configuration apply
After=systemd-hostnamed.service
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/control-center-hostname-apply
UNIT
cat >/etc/systemd/system/control-center-hostname-apply.path <<'UNIT'
[Unit]
Description=Control Center hostname request watcher
[Path]
PathExists=/var/lib/control-center/hostname-pending.json
Unit=control-center-hostname-apply.service
[Install]
WantedBy=multi-user.target
UNIT
cat >/etc/systemd/system/control-center-samba-apply.service <<'UNIT'
[Unit]
Description=Control Center Domain provisioning orchestrator
After=network-online.target postgresql.service control-center-dns-apply.service control-center-storage-apply.service
Wants=network-online.target
[Service]
Type=oneshot
EnvironmentFile=-/etc/control-center/database.env
ExecStartPre=/usr/local/sbin/control-center-samba-package-guard snapshot
ExecStart=/usr/local/sbin/control-center-domain-orchestrate
ExecStartPost=/usr/local/sbin/control-center-samba-package-guard commit
ExecStopPost=/usr/local/sbin/control-center-samba-package-guard restore
TimeoutStartSec=45min
UNIT
cat >/etc/systemd/system/control-center-samba-apply.path <<'UNIT'
[Unit]
Description=Control Center Domain provisioning request watcher
[Path]
PathExists=/run/control-center/samba-provision.json
Unit=control-center-samba-apply.service
[Install]
WantedBy=multi-user.target
UNIT
cat >/etc/systemd/system/control-center-domain-destroy.service <<'UNIT'
[Unit]
Description=Control Center guarded Domain destruction and cleanup
After=network-online.target postgresql.service
[Service]
Type=oneshot
EnvironmentFile=-/etc/control-center/database.env
ExecStart=/usr/local/sbin/control-center-domain-destroy
TimeoutStartSec=30min
UNIT
cat >/etc/systemd/system/control-center-domain-destroy.path <<'UNIT'
[Unit]
Description=Control Center Domain removal request watcher
[Path]
PathExists=/run/control-center/domain-remove.json
Unit=control-center-domain-destroy.service
[Install]
WantedBy=multi-user.target
UNIT
cat >/etc/systemd/system/control-center-dns-apply.service <<'UNIT'
[Unit]
Description=Control Center DNS lifecycle
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/control-center-dns-apply
TimeoutStartSec=20min
UNIT
cat >/etc/systemd/system/control-center-dns-apply.path <<'UNIT'
[Unit]
Description=Control Center DNS request watcher
[Path]
PathExists=/var/lib/control-center/dns-pending.json
Unit=control-center-dns-apply.service
[Install]
WantedBy=multi-user.target
UNIT
cat >/etc/systemd/system/control-center-storage-apply.service <<'UNIT'
[Unit]
Description=Control Center Network Storage lifecycle
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/control-center-storage-apply
TimeoutStartSec=20min
UNIT
cat >/etc/systemd/system/control-center-storage-apply.path <<'UNIT'
[Unit]
Description=Control Center Network Storage request watcher
[Path]
PathExists=/var/lib/control-center/storage-pending.json
Unit=control-center-storage-apply.service
[Install]
WantedBy=multi-user.target
UNIT
cat >/etc/systemd/system/control-center-dhcp-reservations-apply.service <<'UNIT'
[Unit]
Description=Control Center DHCP reservation apply
After=control-center-dhcp-server.service
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/control-center-dhcp-reservations-apply
UNIT
cat >/etc/systemd/system/control-center-dhcp-reservations-apply.path <<'UNIT'
[Unit]
Description=Control Center DHCP reservation request watcher
[Path]
PathExists=/var/lib/control-center/dhcp-reservations-pending.json
Unit=control-center-dhcp-reservations-apply.service
[Install]
WantedBy=multi-user.target
UNIT
cat >/etc/systemd/system/control-center-dhcp-server.service <<'UNIT'
[Unit]
Description=Control Center DHCP Server
After=network-online.target
Wants=network-online.target
ConditionPathExists=/etc/dnsmasq.d/control-center-dhcp.conf
[Service]
Type=simple
ExecStart=/usr/sbin/dnsmasq --keep-in-foreground --conf-file=/etc/dnsmasq.d/control-center-dhcp.conf --conf-file=/etc/dnsmasq.d/control-center-dhcp-reservations.conf
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
[Install]
WantedBy=multi-user.target
UNIT
cat >/etc/systemd/system/control-center-db-migrate.service <<'UNIT'
[Unit]
Description=Control Center PostgreSQL schema migration
After=postgresql.service
Wants=postgresql.service
[Service]
Type=oneshot
User=control-center
Group=control-center
EnvironmentFile=-/etc/control-center/database.env
ExecStart=/opt/control-center/venv/bin/python /opt/control-center/app/db_migrate.py
Restart=on-failure
RestartSec=30s
[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now control-center-authd.service
systemctl enable --now control-center-hostname-apply.path
systemctl enable --now control-center-samba-apply.path
systemctl enable --now control-center-domain-destroy.path
systemctl enable --now control-center-dns-apply.path
systemctl enable --now control-center-storage-apply.path
systemctl enable --now control-center-dhcp-reservations-apply.path
systemctl enable control-center-db-migrate.service
systemctl restart control-center-db-migrate.service || true
if systemctl is-active --quiet control-center-dhcp-server.service; then systemctl restart control-center-dhcp-server.service; fi
systemctl restart control-center

SCHEME=http; CURL=(-fsS --max-time 3)
if [[ "$SSL" == 1 || "$SSL" == true ]]; then SCHEME=https; CURL=(-kfsS --max-time 3); fi
for _ in $(seq 1 25); do if curl "${CURL[@]}" "$SCHEME://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then break; fi; sleep 1; done
curl "${CURL[@]}" "$SCHEME://127.0.0.1:$PORT/api/health" >/dev/null
systemctl is-active --quiet control-center-authd.service
test -S /run/control-center-auth/auth.sock
test "$(stat -c '%U:%G %a' /run/control-center-auth/auth.sock)" = 'root:control-center 660'

for f in \
  /usr/local/sbin/control-center-samba-apply-core \
  /usr/local/sbin/control-center-samba-apply \
  /usr/local/sbin/control-center-domain-pre \
  /usr/local/sbin/control-center-domain-post \
  /usr/local/sbin/control-center-domain-restore-prestate \
  /usr/local/sbin/control-center-domain-destroy \
  /usr/local/sbin/control-center-samba-approve \
  /usr/local/sbin/control-center-samba-package-guard \
  /usr/local/sbin/control-center-dns-apply \
  /usr/local/sbin/control-center-storage-apply \
  /usr/local/sbin/control-center-dhcp-reservations-apply; do
  bash -n "$f"
done
python3 -m py_compile /usr/local/sbin/control-center-authd

echo 'Control Center 1.0.11 build 20260819.5 установлен.'
echo "Web UI: $SCHEME://SERVER:$PORT"
echo 'Авторизация: локальные PAM-пользователи через изолированный auth daemon; после создания Домена — Local + Domain.'
echo 'Локальные администраторы портала: группа control-center-admins. Root через Web запрещён.'
echo 'Маркет: Домен, DNS и Сетевое хранилище активированы; DHCP поддерживает список клиентов и IP-бронирования.'
echo 'Перед созданием Домена: sudo control-center-samba-approve'
echo 'Перед удалением Домена: sudo control-center-samba-approve --remove'
