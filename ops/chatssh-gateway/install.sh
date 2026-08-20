#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo 'ERROR: run as root' >&2
  exit 1
fi

SOURCE_SHA="${CHATSSH_SOURCE_SHA:-6814bae3957a52bbf331a3f2400d5a8be1e16565}"
REPO="${CHATSSH_REPO:-ControlCenterSoft/srv-deployment}"
AGENT_URL="https://raw.githubusercontent.com/${REPO}/${SOURCE_SHA}/ops/chatssh-gateway/agent.py"

for bin in curl git python3 systemctl sha256sum; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: missing $bin" >&2; exit 1; }
done

install -d -m 0755 /usr/local/libexec
install -d -m 0700 /var/lib/chatssh-gateway

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
curl -fsSL "$AGENT_URL" -o "$tmp"
python3 -m py_compile "$tmp"
install -m 0750 "$tmp" /usr/local/libexec/chatssh-gateway

cat >/etc/systemd/system/chatssh-gateway.service <<'UNIT'
[Unit]
Description=Control Center ChatSSH GitHub gateway
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=root
Group=root
Environment=CHATSSH_REPO=ControlCenterSoft/srv-deployment
Environment=CHATSSH_COMMAND_BRANCH=ops/chatssh-control
Environment=CHATSSH_RESULT_BRANCH=ops/chatssh-results
Environment=CHATSSH_STATE_DIR=/var/lib/chatssh-gateway
ExecStart=/usr/local/libexec/chatssh-gateway
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=/var/lib/chatssh-gateway
NoNewPrivileges=false
TimeoutStartSec=1900
UNIT

cat >/etc/systemd/system/chatssh-gateway.timer <<'UNIT'
[Unit]
Description=Poll Control Center ChatSSH command queue

[Timer]
OnBootSec=20s
OnUnitActiveSec=30s
AccuracySec=5s
Persistent=true
Unit=chatssh-gateway.service

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable --now chatssh-gateway.timer
systemctl start chatssh-gateway.service || true

echo 'CHATSSH_GATEWAY_INSTALLED=1'
systemctl is-enabled chatssh-gateway.timer
systemctl is-active chatssh-gateway.timer
