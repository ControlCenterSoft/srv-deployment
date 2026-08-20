#!/usr/bin/env bash
set -Eeuo pipefail

printf 'CHATSSH_DIAGNOSTICS=1\n'
printf 'timestamp=%s\n' "$(date -Is)"
printf 'hostname=%s\n' "$(hostname)"
printf 'kernel=%s\n' "$(uname -srmo)"
printf 'user=%s uid=%s\n' "$(id -un)" "$(id -u)"

printf '\n[ssh-service]\n'
systemctl is-enabled ssh.service 2>&1 || true
systemctl is-active ssh.service 2>&1 || true
systemctl status ssh.service --no-pager -l 2>&1 | tail -n 25 || true

printf '\n[listeners]\n'
ss -lntp 2>&1 | grep -E ':(22|2222|8876)\\b' || true

printf '\n[sshd-effective]\n'
/usr/sbin/sshd -T 2>/dev/null | grep -E '^(port|listenaddress|permitrootlogin|passwordauthentication|pubkeyauthentication|maxauthtries) ' || true

printf '\n[authorized-keys]\n'
if [[ -f /root/.ssh/authorized_keys ]]; then
  printf 'count=%s\n' "$(grep -cEv '^[[:space:]]*(#|$)' /root/.ssh/authorized_keys || true)"
  command -v ssh-keygen >/dev/null && ssh-keygen -lf /root/.ssh/authorized_keys 2>/dev/null || true
else
  echo 'missing'
fi

printf '\n[github-connectivity]\n'
curl -fsSI --max-time 15 https://github.com/ 2>&1 | sed -n '1,5p' || true

printf '\n[existing-agents]\n'
for unit in srvcc-github-agent.timer srv-deploy-agent.service chatssh-gateway.timer chatssh-gateway.service; do
  printf '%s enabled=' "$unit"
  systemctl is-enabled "$unit" 2>/dev/null || true
  printf '%s active=' "$unit"
  systemctl is-active "$unit" 2>/dev/null || true
done

printf '\n[deployment-checkout]\n'
if [[ -d /opt/srv-deployment/.git ]]; then
  git -C /opt/srv-deployment status --short --branch 2>&1 || true
  url="$(git -C /opt/srv-deployment remote get-url origin 2>/dev/null || true)"
  printf 'origin=%s\n' "$(printf '%s' "$url" | sed -E 's#(https://)[^/@]+@#\\1***@#')"
else
  echo '/opt/srv-deployment git checkout absent'
fi
