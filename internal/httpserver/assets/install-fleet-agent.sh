#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

AGENT_VERSION="1.1.0"
AGENT_SHA256="__AGENT_SHA256__"
AGENT_USER="control-center-fleet"
CONFIG_DIR="/etc/control-center-fleet-agent"
STATE_DIR="/var/lib/control-center-fleet-agent"
AGENT_PATH="/usr/local/libexec/control-center-fleet-agent"
CONFIG_PATH="$CONFIG_DIR/agent.conf"
CREDENTIAL_PATH="$STATE_DIR/agent-credential"
TOKEN_TMP=""
AGENT_TMP=""

fail() {
  printf 'FLEET_AGENT_INSTALL_ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  [[ -n "$TOKEN_TMP" ]] && rm -f -- "$TOKEN_TMP"
  [[ -n "$AGENT_TMP" ]] && rm -f -- "$AGENT_TMP"
}
trap cleanup EXIT

[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "run as root"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"
command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"
command -v stat >/dev/null 2>&1 || fail "stat is required"
command -v systemctl >/dev/null 2>&1 || fail "systemd is required"
command -v useradd >/dev/null 2>&1 || fail "useradd is required"

CONTROL_CENTER_URL="${CONTROL_CENTER_URL:-}"
FLEET_NODE_ID="${FLEET_NODE_ID:-}"
FLEET_ENROLLMENT_TOKEN_FILE="${FLEET_ENROLLMENT_TOKEN_FILE:-}"
FLEET_REENROLL="${FLEET_REENROLL:-0}"

[[ -n "$CONTROL_CENTER_URL" ]] || fail "CONTROL_CENTER_URL is required"
CONTROL_CENTER_URL="$(python3 - "$CONTROL_CENTER_URL" <<'PY'
import sys
import urllib.parse

value = sys.argv[1].strip()
try:
    parsed = urllib.parse.urlsplit(value)
except ValueError:
    raise SystemExit(1)
if parsed.username is not None or parsed.password is not None:
    raise SystemExit(1)
if parsed.query or parsed.fragment or parsed.path not in {"", "/"}:
    raise SystemExit(1)
host = (parsed.hostname or "").lower()
if not host:
    raise SystemExit(1)
if parsed.scheme == "https":
    pass
elif parsed.scheme == "http" and host in {"127.0.0.1", "::1", "localhost"}:
    pass
else:
    raise SystemExit(1)
try:
    port = parsed.port
except ValueError:
    raise SystemExit(1)
netloc = host
if ":" in netloc:
    netloc = f"[{netloc}]"
if port is not None:
    netloc = f"{netloc}:{port}"
print(f"{parsed.scheme}://{netloc}")
PY
)" || fail "CONTROL_CENTER_URL must be an HTTPS origin; HTTP is allowed only for loopback testing"
[[ "$FLEET_NODE_ID" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$ ]] || fail "invalid FLEET_NODE_ID"
FLEET_NODE_ID="${FLEET_NODE_ID,,}"
[[ "$FLEET_REENROLL" == 0 || "$FLEET_REENROLL" == 1 ]] || fail "FLEET_REENROLL must be 0 or 1"

if ! id "$AGENT_USER" >/dev/null 2>&1; then
  useradd --system --home-dir "$STATE_DIR" --shell /usr/sbin/nologin "$AGENT_USER"
fi
install -d -m 0750 -o root -g "$AGENT_USER" "$CONFIG_DIR"
install -d -m 0700 -o "$AGENT_USER" -g "$AGENT_USER" "$STATE_DIR"
install -d -m 0755 /usr/local/libexec

AGENT_TMP="$(mktemp /tmp/control-center-fleet-agent.XXXXXX)"
curl --fail --silent --show-error --proto '=https' \
  --max-time 30 "$CONTROL_CENTER_URL/api/v1/fleet/agent/agent.py" -o "$AGENT_TMP" || {
    if [[ "$CONTROL_CENTER_URL" == http://127.0.0.1* || "$CONTROL_CENTER_URL" == http://localhost* || "$CONTROL_CENTER_URL" == http://\[::1\]* ]]; then
      curl --fail --silent --show-error --max-time 30 \
        "$CONTROL_CENTER_URL/api/v1/fleet/agent/agent.py" -o "$AGENT_TMP"
    else
      fail "cannot download fleet agent"
    fi
  }
[[ "$(sha256sum "$AGENT_TMP" | awk '{print $1}')" == "$AGENT_SHA256" ]] || fail "fleet agent digest mismatch"
python3 -m py_compile "$AGENT_TMP" || fail "fleet agent syntax validation failed"
install -m 0755 -o root -g root "$AGENT_TMP" "$AGENT_PATH"

cat >"$CONFIG_PATH" <<EOF
CONTROL_CENTER_URL=$CONTROL_CENTER_URL
FLEET_NODE_ID=$FLEET_NODE_ID
EOF
chown root:"$AGENT_USER" "$CONFIG_PATH"
chmod 0640 "$CONFIG_PATH"

cat >/etc/systemd/system/control-center-fleet-agent.service <<EOF
[Unit]
Description=Control Center Fleet heartbeat agent
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=$AGENT_USER
Group=$AGENT_USER
WorkingDirectory=$STATE_DIR
ExecStart=/usr/bin/python3 $AGENT_PATH --config $CONFIG_PATH --credential-file $CREDENTIAL_PATH
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectClock=true
RestrictSUIDSGID=true
RestrictRealtime=true
RestrictNamespaces=true
LockPersonality=true
CapabilityBoundingSet=
AmbientCapabilities=
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
ReadWritePaths=$STATE_DIR

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/control-center-fleet-agent.timer <<'EOF'
[Unit]
Description=Send Control Center Fleet heartbeat every minute

[Timer]
OnBootSec=30s
OnUnitActiveSec=60s
AccuracySec=5s
RandomizedDelaySec=5s
Persistent=true
Unit=control-center-fleet-agent.service

[Install]
WantedBy=timers.target
EOF

need_enrollment=0
if [[ ! -s "$CREDENTIAL_PATH" || "$FLEET_REENROLL" == 1 ]]; then
  need_enrollment=1
fi

if [[ "$need_enrollment" == 1 ]]; then
  TOKEN_TMP="$(mktemp /tmp/control-center-fleet-token.XXXXXX)"
  chmod 0600 "$TOKEN_TMP"
  if [[ -n "$FLEET_ENROLLMENT_TOKEN_FILE" ]]; then
    [[ -f "$FLEET_ENROLLMENT_TOKEN_FILE" && ! -L "$FLEET_ENROLLMENT_TOKEN_FILE" ]] \
      || fail "FLEET_ENROLLMENT_TOKEN_FILE must be a regular file"
    token_mode="$(stat -c '%a' "$FLEET_ENROLLMENT_TOKEN_FILE")"
    token_uid="$(stat -c '%u' "$FLEET_ENROLLMENT_TOKEN_FILE")"
    [[ "$token_uid" == 0 ]] || fail "enrollment token file must be owned by root"
    [[ "$token_mode" == 600 || "$token_mode" == 400 ]] || fail "enrollment token file must have mode 0600 or 0400"
    cat -- "$FLEET_ENROLLMENT_TOKEN_FILE" >"$TOKEN_TMP"
  elif [[ -r /dev/tty ]]; then
    printf 'One-time Fleet enrollment token: ' >/dev/tty
    IFS= read -r -s token </dev/tty || fail "cannot read enrollment token"
    printf '\n' >/dev/tty
    [[ -n "$token" ]] || fail "empty enrollment token"
    printf '%s\n' "$token" >"$TOKEN_TMP"
    unset token
  else
    fail "enrollment token required: use an interactive terminal or FLEET_ENROLLMENT_TOKEN_FILE"
  fi
  /usr/bin/python3 "$AGENT_PATH" \
    --config "$CONFIG_PATH" \
    --credential-file "$CREDENTIAL_PATH" \
    --enroll-token-file "$TOKEN_TMP"
  chown "$AGENT_USER:$AGENT_USER" "$CREDENTIAL_PATH"
  chmod 0600 "$CREDENTIAL_PATH"
fi

systemctl daemon-reload
systemctl enable --now control-center-fleet-agent.timer
systemctl start control-center-fleet-agent.service || fail "initial heartbeat failed"
systemctl is-enabled --quiet control-center-fleet-agent.timer || fail "fleet heartbeat timer is not enabled"
systemctl is-active --quiet control-center-fleet-agent.timer || fail "fleet heartbeat timer is not active"
[[ "$(systemctl show control-center-fleet-agent.service -p User --value)" == "$AGENT_USER" ]] \
  || fail "fleet agent does not run as the dedicated user"
[[ "$(systemctl show control-center-fleet-agent.service -p NoNewPrivileges --value)" == yes ]] \
  || fail "NoNewPrivileges hardening is not active"
[[ "$(systemctl show control-center-fleet-agent.service -p CapabilityBoundingSet --value)" == "" ]] \
  || fail "fleet agent capability bounding set is not empty"

printf 'CONTROL_CENTER_FLEET_AGENT_INSTALL=PASSED\n'
printf 'FLEET_NODE_ID=%s\n' "$FLEET_NODE_ID"
printf 'FLEET_AGENT_VERSION=%s\n' "$AGENT_VERSION"
printf 'HEARTBEAT_INTERVAL_SECONDS=60\n'
printf 'RUNTIME_USER=%s\n' "$AGENT_USER"
printf 'ARBITRARY_SHELL=disabled\n'
printf 'CREDENTIAL_STORAGE=%s\n' "$CREDENTIAL_PATH"
