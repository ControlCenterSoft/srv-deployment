#!/usr/bin/env bash
set -Eeuo pipefail

MODE="install"
if [[ ${1:-} == "--repair" ]]; then MODE="repair"; shift; fi
if [[ ${1:-} == "--reinstall" ]]; then MODE="reinstall"; shift; fi
if [[ $# -ne 0 ]]; then echo "Usage: $0 [--repair|--reinstall]" >&2; exit 2; fi

INSTALL_ROOT="/usr/local/lib/control-center"
RELEASES_DIR="$INSTALL_ROOT/releases"
STAGING_DIR="$INSTALL_ROOT/staging"
CURRENT_LINK="$INSTALL_ROOT/current"
PREVIOUS_LINK="$INSTALL_ROOT/previous"
LEGACY_BINARY="$INSTALL_ROOT/control-center"
UPDATE_SCRIPT="/usr/local/sbin/control-center-update"
CONFIG_DIR="/etc/control-center"
STATE_DIR="/var/lib/control-center"
LOG_DIR="/var/log/control-center"
PRIVILEGED_LOG_DIR="/var/log/control-center-privileged"
UNIT_PATH="/etc/systemd/system/control-center.service"
WORKER_UNIT_PATH="/etc/systemd/system/control-center-privileged-worker.service"
ENV_PATH="$CONFIG_DIR/control-center.env"
TRUST_KEY="$CONFIG_DIR/update-public-key.pem"
ACCEPTANCE_URL="${CONTROL_CENTER_ACCEPTANCE_URL:-http://127.0.0.1:8876}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

log() { printf '[control-center] %s\n' "$*"; }
die() { printf '[control-center] ERROR: %s\n' "$*" >&2; exit 1; }
atomic_link() { local target="$1" link="$2" tmp="${2}.new.$$"; rm -f -- "$tmp"; ln -s -- "$target" "$tmp"; mv -Tf -- "$tmp" "$link"; }

[[ $EUID -eq 0 ]] || die "installer must run as root"
for cmd in systemctl install curl runuser sha256sum stat; do command -v "$cmd" >/dev/null || die "$cmd is required"; done
[[ -d /run/systemd/system ]] || die "systemd is not running"
arch="$(uname -m)"
case "$arch" in x86_64) artifact_arch="amd64" ;; aarch64|arm64) artifact_arch="arm64" ;; *) die "unsupported architecture: $arch" ;; esac
binary="${CONTROL_CENTER_BINARY:-$REPO_ROOT/dist/control-center-linux-$artifact_arch}"
worker_binary="${CONTROL_CENTER_PRIVILEGED_WORKER_BINARY:-$REPO_ROOT/dist/control-center-privileged-worker-linux-$artifact_arch}"
[[ -f "$binary" && ! -L "$binary" ]] || die "binary not found or invalid: $binary"
[[ -f "$worker_binary" && ! -L "$worker_binary" ]] || die "privileged worker binary not found or invalid: $worker_binary"
[[ -f "$REPO_ROOT/packaging/systemd/control-center.service" ]] || die "systemd unit template is missing"
[[ -f "$REPO_ROOT/packaging/systemd/control-center-privileged-worker.service" ]] || die "privileged worker unit template is missing"
[[ -f "$REPO_ROOT/install/update-v2.sh" ]] || die "update v2 script is missing"

version="$("$binary" build-info --field version)" || die "candidate cannot report version"
commit="$("$binary" build-info --field commit)" || die "candidate cannot report commit"
"$binary" compare-version --current "$version" --target "$version" >/dev/null || die "invalid candidate version: $version"
[[ "$commit" =~ ^[0-9a-f]{7,64}$|^unknown$ ]] || die "invalid candidate commit: $commit"
sha="$(sha256sum "$binary" | awk '{print $1}')"
worker_sha="$(sha256sum "$worker_binary" | awk '{print $1}')"
[[ "$worker_sha" =~ ^[0-9a-f]{64}$ ]] || die "invalid privileged worker sha256"
commit_id="${commit:0:12}"
release_id="$version-$commit_id-${sha:0:12}"
release_rel="releases/$release_id"
release_dir="$RELEASES_DIR/$release_id"

backup="$(mktemp -d /tmp/control-center-install.XXXXXX)"
cleanup() { rm -rf -- "$backup"; }
trap cleanup EXIT

had_unit=0; had_worker_unit=0; had_env=0; had_update=0; had_key=0; had_legacy=0
had_config_dir=0; had_state_dir=0; had_log_dir=0; had_privileged_log_dir=0; had_user=0; had_group=0
was_enabled=0; was_active=0; worker_was_enabled=0; worker_was_active=0
old_current=""; old_previous=""; created_release=0
[[ -d "$CONFIG_DIR" ]] && had_config_dir=1; [[ -d "$STATE_DIR" ]] && had_state_dir=1; [[ -d "$LOG_DIR" ]] && had_log_dir=1
[[ -d "$PRIVILEGED_LOG_DIR" ]] && had_privileged_log_dir=1
getent group control-center >/dev/null && had_group=1 || true
id -u control-center >/dev/null 2>&1 && had_user=1 || true
systemctl is-enabled --quiet control-center.service 2>/dev/null && was_enabled=1 || true
systemctl is-active --quiet control-center.service 2>/dev/null && was_active=1 || true
systemctl is-enabled --quiet control-center-privileged-worker.service 2>/dev/null && worker_was_enabled=1 || true
systemctl is-active --quiet control-center-privileged-worker.service 2>/dev/null && worker_was_active=1 || true
[[ -L "$CURRENT_LINK" ]] && old_current="$(readlink "$CURRENT_LINK")"
[[ -L "$PREVIOUS_LINK" ]] && old_previous="$(readlink "$PREVIOUS_LINK")"
if [[ -f "$UNIT_PATH" ]]; then cp -a -- "$UNIT_PATH" "$backup/unit"; had_unit=1; fi
if [[ -f "$WORKER_UNIT_PATH" ]]; then cp -a -- "$WORKER_UNIT_PATH" "$backup/worker-unit"; had_worker_unit=1; fi
if [[ -f "$ENV_PATH" ]]; then cp -a -- "$ENV_PATH" "$backup/env"; had_env=1; fi
if [[ -f "$UPDATE_SCRIPT" ]]; then cp -a -- "$UPDATE_SCRIPT" "$backup/update"; had_update=1; fi
if [[ -f "$TRUST_KEY" ]]; then cp -a -- "$TRUST_KEY" "$backup/key"; had_key=1; fi
if [[ -f "$LEGACY_BINARY" ]]; then cp -a -- "$LEGACY_BINARY" "$backup/legacy"; had_legacy=1; fi

rollback() {
  rc=$?; trap - ERR
  log "installation failed; restoring previous runtime state"
  systemctl disable --now control-center.service >/dev/null 2>&1 || true
  systemctl disable --now control-center-privileged-worker.service >/dev/null 2>&1 || true
  rm -f -- "$CURRENT_LINK" "$PREVIOUS_LINK"
  [[ -n "$old_current" ]] && atomic_link "$old_current" "$CURRENT_LINK"
  [[ -n "$old_previous" ]] && atomic_link "$old_previous" "$PREVIOUS_LINK"
  (( had_unit )) && install -D -m 0644 "$backup/unit" "$UNIT_PATH" || rm -f -- "$UNIT_PATH"
  (( had_worker_unit )) && install -D -m 0644 "$backup/worker-unit" "$WORKER_UNIT_PATH" || rm -f -- "$WORKER_UNIT_PATH"
  (( had_env )) && install -D -m 0640 "$backup/env" "$ENV_PATH" || rm -f -- "$ENV_PATH"
  (( had_update )) && install -D -m 0755 "$backup/update" "$UPDATE_SCRIPT" || rm -f -- "$UPDATE_SCRIPT"
  (( had_key )) && install -D -m 0644 "$backup/key" "$TRUST_KEY" || rm -f -- "$TRUST_KEY"
  (( had_legacy )) && install -D -m 0755 "$backup/legacy" "$LEGACY_BINARY" || rm -f -- "$LEGACY_BINARY"
  (( created_release )) && rm -rf -- "$release_dir"
  systemctl daemon-reload || true
  (( worker_was_enabled )) && systemctl enable control-center-privileged-worker.service >/dev/null 2>&1 || true
  (( was_enabled )) && systemctl enable control-center.service >/dev/null 2>&1 || true
  (( worker_was_active )) && systemctl start control-center-privileged-worker.service >/dev/null 2>&1 || true
  (( was_active )) && systemctl start control-center.service >/dev/null 2>&1 || true
  (( ! had_config_dir )) && rm -rf -- "$CONFIG_DIR"
  (( ! had_state_dir )) && rm -rf -- "$STATE_DIR"
  (( ! had_log_dir )) && rm -rf -- "$LOG_DIR"
  (( ! had_privileged_log_dir )) && rm -rf -- "$PRIVILEGED_LOG_DIR"
  if (( ! had_user )) && id -u control-center >/dev/null 2>&1; then userdel control-center >/dev/null 2>&1 || true; fi
  if (( ! had_group )) && getent group control-center >/dev/null; then groupdel control-center >/dev/null 2>&1 || true; fi
  exit "$rc"
}
trap rollback ERR

(( had_group )) || groupadd --system control-center
if (( ! had_user )); then useradd --system --gid control-center --home-dir "$STATE_DIR" --no-create-home --shell /usr/sbin/nologin control-center; fi
install -d -o root -g root -m 0755 "$INSTALL_ROOT" "$RELEASES_DIR" "$STAGING_DIR"
if [[ ! -d "$release_dir" ]]; then
  tmp_release="$(mktemp -d "$RELEASES_DIR/.install.XXXXXX")"
  install -m 0555 "$binary" "$tmp_release/control-center"
  install -m 0555 "$worker_binary" "$tmp_release/control-center-privileged-worker"
  printf '%s  %s\n' "$sha" control-center > "$tmp_release/SHA256SUMS"
  printf '%s  %s\n' "$worker_sha" control-center-privileged-worker >> "$tmp_release/SHA256SUMS"
  chmod 0444 "$tmp_release/SHA256SUMS"
  chmod 0555 "$tmp_release"
  mv -- "$tmp_release" "$release_dir"
  created_release=1
else
  [[ -f "$release_dir/control-center" && -f "$release_dir/control-center-privileged-worker" ]] || die "existing release is missing required runtime artifacts"
  cmp -s -- "$binary" "$release_dir/control-center" || die "release id collision with different binary"
  cmp -s -- "$worker_binary" "$release_dir/control-center-privileged-worker" || die "release id collision with different privileged worker"
fi
install -m 0644 "$REPO_ROOT/packaging/systemd/control-center.service" "$UNIT_PATH"
install -m 0644 "$REPO_ROOT/packaging/systemd/control-center-privileged-worker.service" "$WORKER_UNIT_PATH"
install -m 0755 "$REPO_ROOT/install/update-v2.sh" "$UPDATE_SCRIPT"
install -d -o root -g control-center -m 0750 "$CONFIG_DIR"
install -d -o control-center -g control-center -m 0750 "$STATE_DIR" "$LOG_DIR"
install -d -o root -g root -m 0700 "$PRIVILEGED_LOG_DIR"
if [[ ! -f "$ENV_PATH" ]]; then printf '%s\n' 'CONTROL_CENTER_LISTEN=127.0.0.1:8876' > "$ENV_PATH"; chown root:control-center "$ENV_PATH"; chmod 0640 "$ENV_PATH"; fi
if [[ -n ${CONTROL_CENTER_UPDATE_PUBLIC_KEY:-} ]]; then
  [[ -f "$CONTROL_CENTER_UPDATE_PUBLIC_KEY" ]] || die "configured update public key does not exist"
  install -o root -g root -m 0644 "$CONTROL_CENTER_UPDATE_PUBLIC_KEY" "$TRUST_KEY"
fi

bootstrap_output="$(runuser -u control-center -- "$release_dir/control-center" bootstrap-admin --username admin)"
log "$bootstrap_output"
if [[ -f "$STATE_DIR/bootstrap-admin.secret" ]]; then chmod 0600 "$STATE_DIR/bootstrap-admin.secret"; log "Initial credentials are root-readable at $STATE_DIR/bootstrap-admin.secret and are deleted after the first password change."; fi
atomic_link "$release_rel" "$CURRENT_LINK"
systemctl daemon-reload
systemctl enable control-center-privileged-worker.service control-center.service >/dev/null
systemctl reset-failed control-center-privileged-worker.service control-center.service >/dev/null 2>&1 || true
systemctl restart control-center-privileged-worker.service
for _ in {1..20}; do
  if systemctl is-active --quiet control-center-privileged-worker.service && [[ -S /run/control-center/privileged-worker.sock ]]; then
    socket_owner="$(stat -c '%U:%G:%a' /run/control-center/privileged-worker.sock)"
    [[ "$socket_owner" == "root:control-center:660" ]] || die "privileged worker socket ownership/mode rejected: $socket_owner"
    break
  fi
  sleep 0.25
done
systemctl is-active --quiet control-center-privileged-worker.service || die "privileged worker did not become active"
[[ -S /run/control-center/privileged-worker.sock ]] || die "privileged worker socket did not become ready"
systemctl restart control-center.service
for _ in {1..24}; do
  if curl -fsS --max-time 2 "${ACCEPTANCE_URL}/api/v1/health" >/dev/null 2>&1 && curl -fsS --max-time 2 "${ACCEPTANCE_URL}/api/v1/readiness" | grep -Fq '"ready":true'; then
    trap - ERR
    rm -f -- "$LEGACY_BINARY"
    log "$MODE completed; current=$release_rel privileged-worker=active updater=v2"
    [[ -f "$TRUST_KEY" ]] || log "Update trust key is not configured; signed updates remain disabled until $TRUST_KEY is provisioned."
    exit 0
  fi
  sleep 0.25
done
die "runtime did not become ready"
