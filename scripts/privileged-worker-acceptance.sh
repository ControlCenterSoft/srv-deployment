#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE="control-center-privileged.service"
WEB_SERVICE="control-center.service"
BIN="/usr/local/lib/control-center/current/control-center"
SOCKET="/run/control-center-privileged/worker.sock"

fail() { printf 'PRIVILEGED_ACCEPTANCE=FAILED reason=%s\n' "$*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || fail "must_run_as_root"
for cmd in systemctl runuser stat id; do command -v "$cmd" >/dev/null || fail "missing_$cmd"; done
[[ -x "$BIN" ]] || fail "runtime_missing"
systemctl is-active --quiet "$SERVICE" || fail "worker_inactive"
systemctl is-active --quiet "$WEB_SERVICE" || fail "web_inactive"
[[ -S "$SOCKET" ]] || fail "socket_missing"

owner="$(stat -c '%U:%G' "$SOCKET")"
mode="$(stat -c '%a' "$SOCKET")"
[[ "$owner" == "root:control-center" ]] || fail "socket_owner_$owner"
[[ "$mode" == "660" ]] || fail "socket_mode_$mode"

[[ "$(systemctl show "$SERVICE" -p User --value)" == "root" ]] || fail "worker_user"
[[ "$(systemctl show "$SERVICE" -p Group --value)" == "control-center" ]] || fail "worker_group"
[[ "$(systemctl show "$SERVICE" -p NoNewPrivileges --value)" == "yes" ]] || fail "worker_no_new_privileges"
[[ "$(systemctl show "$WEB_SERVICE" -p User --value)" == "control-center" ]] || fail "web_user"
[[ "$(systemctl show "$WEB_SERVICE" -p NoNewPrivileges --value)" == "yes" ]] || fail "web_no_new_privileges"

runuser -u control-center -- "$BIN" privileged-call \
  --action systemd.unit.status \
  --target control-center.service \
  --operation-id aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa >/tmp/control-center-privileged-status.json || fail "allowed_status_failed"
grep -Fq '"status":"succeeded"' /tmp/control-center-privileged-status.json || fail "allowed_status_not_succeeded"

if runuser -u control-center -- "$BIN" privileged-call \
  --action systemd.unit.status \
  --target ssh.service \
  --operation-id bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb >/dev/null 2>&1; then
  fail "nonallowlisted_target_succeeded"
fi

if runuser -u control-center -- "$BIN" privileged-call \
  --action systemd.unit.restart \
  --target control-center.service \
  --operation-id cccccccccccccccccccccccccccccccc >/dev/null 2>&1; then
  fail "disabled_action_succeeded"
fi

if "$BIN" privileged-call \
  --action systemd.unit.status \
  --target control-center.service \
  --operation-id dddddddddddddddddddddddddddddddd >/dev/null 2>&1; then
  fail "root_peer_succeeded"
fi

rm -f /tmp/control-center-privileged-status.json
printf 'PRIVILEGED_ACCEPTANCE=PASSED\n'
