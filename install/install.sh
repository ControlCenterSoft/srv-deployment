#!/usr/bin/env bash
set -Eeuo pipefail

MODE="install"
if [[ ${1:-} == "--repair" ]]; then MODE="repair"; shift; fi
if [[ ${1:-} == "--reinstall" ]]; then MODE="reinstall"; shift; fi
if [[ $# -ne 0 ]]; then echo "Usage: $0 [--repair|--reinstall]" >&2; exit 2; fi

INSTALL_DIR="/usr/local/lib/control-center"
CONFIG_DIR="/etc/control-center"
STATE_DIR="/var/lib/control-center"
LOG_DIR="/var/log/control-center"
UNIT_PATH="/etc/systemd/system/control-center.service"
ENV_PATH="$CONFIG_DIR/control-center.env"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

log() { printf '[control-center] %s\n' "$*"; }
die() { printf '[control-center] ERROR: %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "installer must run as root"
command -v systemctl >/dev/null || die "systemd is required"
command -v install >/dev/null || die "install utility is required"
command -v curl >/dev/null || die "curl is required for local health validation"
command -v runuser >/dev/null || die "runuser is required for account bootstrap"
[[ -d /run/systemd/system ]] || die "systemd is not running"

arch="$(uname -m)"
case "$arch" in
  x86_64) artifact_arch="amd64" ;;
  aarch64|arm64) artifact_arch="arm64" ;;
  *) die "unsupported architecture: $arch" ;;
esac

binary="${CONTROL_CENTER_BINARY:-$REPO_ROOT/dist/control-center-linux-$artifact_arch}"
[[ -f "$binary" ]] || die "binary not found: $binary"
[[ -f "$REPO_ROOT/packaging/systemd/control-center.service" ]] || die "systemd unit template is missing"

backup="$(mktemp -d /tmp/control-center-install.XXXXXX)"
cleanup() { rm -rf -- "$backup"; }
trap cleanup EXIT

had_binary=0; had_unit=0; had_env=0
had_config_dir=0; had_state_dir=0; had_log_dir=0
had_user=0; had_group=0; was_enabled=0; was_active=0
[[ -d "$CONFIG_DIR" ]] && had_config_dir=1
[[ -d "$STATE_DIR" ]] && had_state_dir=1
[[ -d "$LOG_DIR" ]] && had_log_dir=1
if getent group control-center >/dev/null; then had_group=1; fi
if id -u control-center >/dev/null 2>&1; then had_user=1; fi
if systemctl is-enabled --quiet control-center.service 2>/dev/null; then was_enabled=1; fi
if systemctl is-active --quiet control-center.service 2>/dev/null; then was_active=1; fi
if [[ -f "$INSTALL_DIR/control-center" ]]; then cp -a -- "$INSTALL_DIR/control-center" "$backup/control-center"; had_binary=1; fi
if [[ -f "$UNIT_PATH" ]]; then cp -a -- "$UNIT_PATH" "$backup/control-center.service"; had_unit=1; fi
if [[ -f "$ENV_PATH" ]]; then cp -a -- "$ENV_PATH" "$backup/control-center.env"; had_env=1; fi

rollback() {
  rc=$?
  trap - ERR
  log "installation failed; restoring previous runtime state"
  systemctl disable --now control-center.service >/dev/null 2>&1 || true
  if (( had_binary )); then install -D -m 0755 "$backup/control-center" "$INSTALL_DIR/control-center"; else rm -f -- "$INSTALL_DIR/control-center"; fi
  if (( had_unit )); then install -D -m 0644 "$backup/control-center.service" "$UNIT_PATH"; else rm -f -- "$UNIT_PATH"; fi
  if (( had_env )); then install -D -m 0640 "$backup/control-center.env" "$ENV_PATH"; else rm -f -- "$ENV_PATH"; fi
  systemctl daemon-reload || true
  if (( was_enabled )); then systemctl enable control-center.service >/dev/null 2>&1 || true; fi
  if (( was_active )); then systemctl start control-center.service >/dev/null 2>&1 || true; fi

  if (( ! had_config_dir )); then rm -rf -- "$CONFIG_DIR"; fi
  if (( ! had_state_dir )); then rm -rf -- "$STATE_DIR"; fi
  if (( ! had_log_dir )); then rm -rf -- "$LOG_DIR"; fi
  if (( ! had_user )) && id -u control-center >/dev/null 2>&1; then userdel control-center >/dev/null 2>&1 || true; fi
  if (( ! had_group )) && getent group control-center >/dev/null; then groupdel control-center >/dev/null 2>&1 || true; fi
  exit "$rc"
}
trap rollback ERR

if (( ! had_group )); then groupadd --system control-center; fi
if (( ! had_user )); then
  useradd --system --gid control-center --home-dir "$STATE_DIR" --no-create-home --shell /usr/sbin/nologin control-center
fi

install -d -o root -g root -m 0755 "$INSTALL_DIR"
install -m 0755 "$binary" "$INSTALL_DIR/control-center"
install -m 0644 "$REPO_ROOT/packaging/systemd/control-center.service" "$UNIT_PATH"
install -d -o root -g control-center -m 0750 "$CONFIG_DIR"
install -d -o control-center -g control-center -m 0750 "$STATE_DIR" "$LOG_DIR"
if [[ ! -f "$ENV_PATH" ]]; then
  printf '%s\n' 'CONTROL_CENTER_LISTEN=127.0.0.1:8876' > "$ENV_PATH"
  chown root:control-center "$ENV_PATH"
  chmod 0640 "$ENV_PATH"
fi

bootstrap_output="$(runuser -u control-center -- "$INSTALL_DIR/control-center" bootstrap-admin --username admin)"
log "$bootstrap_output"
if [[ -f "$STATE_DIR/bootstrap-admin.secret" ]]; then
  chmod 0600 "$STATE_DIR/bootstrap-admin.secret"
  log "Initial credentials are root-readable at $STATE_DIR/bootstrap-admin.secret and are deleted after the first password change."
fi

systemctl daemon-reload
systemctl enable control-center.service >/dev/null
systemctl restart control-center.service

for _ in {1..20}; do
  if curl --fail --silent --show-error --max-time 2 http://127.0.0.1:8876/api/v1/health >/dev/null; then
    trap - ERR
    log "$MODE completed; runtime health check passed"
    exit 0
  fi
  sleep 0.5
done

die "runtime did not become healthy"
