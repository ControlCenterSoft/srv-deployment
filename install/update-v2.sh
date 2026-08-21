#!/usr/bin/env bash
set -Eeuo pipefail

PACKAGE=""
PUBLIC_KEY="/etc/control-center/update-public-key.pem"
ALLOW_DOWNGRADE=0
while (($#)); do
  case "$1" in
    --package) PACKAGE="${2:-}"; shift 2 ;;
    --public-key) PUBLIC_KEY="${2:-}"; shift 2 ;;
    --allow-downgrade) ALLOW_DOWNGRADE=1; shift ;;
    *) echo "Usage: $0 --package PATH [--public-key PATH] [--allow-downgrade]" >&2; exit 2 ;;
  esac
done

INSTALL_ROOT="${CONTROL_CENTER_INSTALL_ROOT:-/usr/local/lib/control-center}"
RELEASES_DIR="$INSTALL_ROOT/releases"
STAGING_DIR="$INSTALL_ROOT/staging"
CURRENT_LINK="$INSTALL_ROOT/current"
PREVIOUS_LINK="$INSTALL_ROOT/previous"
CURRENT_BIN="$CURRENT_LINK/control-center"
CURRENT_WORKER="$CURRENT_LINK/control-center-privileged-worker"
SERVICE="${CONTROL_CENTER_SERVICE:-control-center.service}"
WORKER_SERVICE="${CONTROL_CENTER_WORKER_SERVICE:-control-center-privileged-worker.service}"
SOCKET="${CONTROL_CENTER_PRIVILEGED_SOCKET:-/run/control-center/privileged-worker.sock}"
BASE_URL="${CONTROL_CENTER_UPDATE_HEALTH_URL:-http://127.0.0.1:8876}"
EXPECTED_SOCKET_GROUP="${CONTROL_CENTER_SOCKET_GROUP:-control-center}"

log() { printf '[control-center-update-v2] %s\n' "$*"; }
die() { printf '[control-center-update-v2] ERROR: %s\n' "$*" >&2; exit 1; }
atomic_link() {
  local target="$1" link="$2" tmp="${2}.new.$$"
  rm -f -- "$tmp"
  ln -s -- "$target" "$tmp"
  mv -Tf -- "$tmp" "$link"
}
unit_enabled() { systemctl is-enabled --quiet "$1"; }
unit_active() { systemctl is-active --quiet "$1"; }

[[ $EUID -eq 0 ]] || die "update must run as root"
[[ -n "$PACKAGE" && -f "$PACKAGE" ]] || die "release package is required"
[[ -f "$PUBLIC_KEY" ]] || die "trusted update public key not found: $PUBLIC_KEY"
[[ -x "$CURRENT_BIN" ]] || die "trusted current runtime not found: $CURRENT_BIN"
[[ -x "$CURRENT_WORKER" && ! -L "$CURRENT_WORKER" ]] || die "trusted current privileged worker not found: $CURRENT_WORKER"
[[ -L "$CURRENT_LINK" ]] || die "current release link is missing"
command -v tar >/dev/null || die "tar is required"
command -v systemctl >/dev/null || die "systemd is required"
command -v curl >/dev/null || die "curl is required"
command -v stat >/dev/null || die "stat is required"
command -v getent >/dev/null || die "getent is required"
systemctl cat "$SERVICE" >/dev/null 2>&1 || die "main systemd unit is not installed: $SERVICE"
systemctl cat "$WORKER_SERVICE" >/dev/null 2>&1 || die "privileged worker systemd unit is not installed: $WORKER_SERVICE"

entries="$(tar -tzf "$PACKAGE")" || die "unable to list release package"
expected=$'bootstrap-manifest.json\nbootstrap-manifest.sig\nmanifest.json\nmanifest.sig\ncontrol-center\ncontrol-center-privileged-worker'
[[ "$entries" == "$expected" ]] || die "release package contains unexpected entries"

install -d -o root -g root -m 0755 "$RELEASES_DIR" "$STAGING_DIR"
stage="$(mktemp -d "$STAGING_DIR/update-v2.XXXXXX")"
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT
tar --no-same-owner --no-same-permissions -xzf "$PACKAGE" -C "$stage"
for f in bootstrap-manifest.json bootstrap-manifest.sig manifest.json manifest.sig control-center control-center-privileged-worker; do
  [[ -f "$stage/$f" && ! -L "$stage/$f" ]] || die "invalid staged entry: $f"
done
chmod 0644 "$stage/bootstrap-manifest.json" "$stage/bootstrap-manifest.sig" "$stage/manifest.json" "$stage/manifest.sig"
chmod 0755 "$stage/control-center" "$stage/control-center-privileged-worker"

bootstrap_field() {
  "$CURRENT_BIN" verify-release \
    --manifest "$stage/bootstrap-manifest.json" \
    --signature "$stage/bootstrap-manifest.sig" \
    --public-key "$PUBLIC_KEY" \
    --artifact "$stage/control-center" \
    --field "$1"
}
bootstrap_version="$(bootstrap_field version)" || die "schema-1 bootstrap verification failed"
bootstrap_commit="$(bootstrap_field commit)" || die "schema-1 bootstrap verification failed"

verify_v2_field() {
  "$stage/control-center" verify-release-v2 \
    --manifest "$stage/manifest.json" \
    --signature "$stage/manifest.sig" \
    --public-key "$PUBLIC_KEY" \
    --artifact "$stage/control-center" \
    --worker "$stage/control-center-privileged-worker" \
    --field "$1"
}
release_id="$(verify_v2_field release-id)" || die "release v2 verification failed"
target_version="$(verify_v2_field version)" || die "release v2 verification failed"
target_commit="$(verify_v2_field commit)" || die "release v2 verification failed"
[[ "$target_version" == "$bootstrap_version" ]] || die "schema-1/schema-2 version identity mismatch"
[[ "$target_commit" == "$bootstrap_commit" ]] || die "schema-1/schema-2 commit identity mismatch"

candidate_version="$("$stage/control-center" build-info --field version)" || die "verified candidate cannot report version"
candidate_commit="$("$stage/control-center" build-info --field commit)" || die "verified candidate cannot report commit"
[[ "$candidate_version" == "$target_version" ]] || die "candidate version does not match signed manifest"
[[ "$candidate_commit" == "$target_commit" ]] || die "candidate commit does not match signed manifest"

current_version="$("$CURRENT_BIN" build-info --field version)"
current_commit="$("$CURRENT_BIN" build-info --field commit)"
comparison="$("$CURRENT_BIN" compare-version --current "$current_version" --target "$target_version")" || die "unable to compare release versions"
if (( comparison == 0 && ! ALLOW_DOWNGRADE )); then
  [[ "$current_version" == "$target_version" ]] || die "equal version comparison returned inconsistent identity"
  [[ "$current_commit" == "$target_commit" ]] || die "target $target_version reuses the current version with a different commit identity"
  cmp -s -- "$stage/control-center" "$CURRENT_BIN" || die "target $target_version reuses the current version/commit with different main runtime bytes"
  cmp -s -- "$stage/control-center-privileged-worker" "$CURRENT_WORKER" || die "target $target_version reuses the current version/commit with different privileged worker bytes"
  log "target $target_version ($target_commit) is already active with exact signed identity; no update required"
  exit 0
fi
if (( comparison > 0 && ! ALLOW_DOWNGRADE )); then
  die "target $target_version is older than current $current_version; use --allow-downgrade only for an explicit controlled rollback"
fi

release_dir="$RELEASES_DIR/$release_id"
release_rel="releases/$release_id"
if [[ -e "$release_dir" ]]; then
  [[ -d "$release_dir" && ! -L "$release_dir" ]] || die "existing release directory is invalid"
  for f in control-center control-center-privileged-worker; do
    [[ -f "$release_dir/$f" && ! -L "$release_dir/$f" ]] || die "existing release artifact is invalid: $f"
    cmp -s -- "$stage/$f" "$release_dir/$f" || die "existing release id has different artifact bytes: $f"
  done
else
  tmp_release="$(mktemp -d "$RELEASES_DIR/.release-v2.XXXXXX")"
  install -m 0555 "$stage/control-center" "$tmp_release/control-center"
  install -m 0555 "$stage/control-center-privileged-worker" "$tmp_release/control-center-privileged-worker"
  install -m 0444 "$stage/bootstrap-manifest.json" "$tmp_release/bootstrap-manifest.json"
  install -m 0444 "$stage/bootstrap-manifest.sig" "$tmp_release/bootstrap-manifest.sig"
  install -m 0444 "$stage/manifest.json" "$tmp_release/manifest.json"
  install -m 0444 "$stage/manifest.sig" "$tmp_release/manifest.sig"
  chmod 0555 "$tmp_release"
  mv -- "$tmp_release" "$release_dir"
fi

old_target="$(readlink "$CURRENT_LINK")"
[[ -n "$old_target" ]] || die "current release target is empty"
worker_was_enabled=0
worker_was_active=0
main_was_enabled=0
main_was_active=0
unit_enabled "$WORKER_SERVICE" && worker_was_enabled=1 || true
unit_active "$WORKER_SERVICE" && worker_was_active=1 || true
unit_enabled "$SERVICE" && main_was_enabled=1 || true
unit_active "$SERVICE" && main_was_active=1 || true

restore_unit_policy() {
  local unit="$1" enabled="$2" active="$3"
  if (( enabled )); then
    systemctl enable "$unit" >/dev/null
  else
    systemctl disable "$unit" >/dev/null
  fi
  if (( active )); then
    systemctl restart "$unit" >/dev/null
  else
    systemctl stop "$unit" >/dev/null
  fi
}
rollback_main_ready() {
  local readiness_body version_body
  systemctl is-active --quiet "$SERVICE" || return 1
  curl -fsS --max-time 2 "${BASE_URL}/api/v1/health" >/dev/null 2>&1 || return 1
  readiness_body="$(curl -fsS --max-time 2 "${BASE_URL}/api/v1/readiness" 2>/dev/null || true)"
  version_body="$(curl -fsS --max-time 2 "${BASE_URL}/api/v1/version" 2>/dev/null || true)"
  grep -Fq '"ready":true' <<<"$readiness_body" && grep -Fq "\"version\":\"$current_version\"" <<<"$version_body"
}
rollback() {
  local reason="$1" rollback_ok=0 worker_restore_failed=0 main_restore_failed=0
  log "$reason; rolling back to $old_target"
  atomic_link "$old_target" "$CURRENT_LINK"
  systemctl reset-failed "$WORKER_SERVICE" "$SERVICE" >/dev/null 2>&1 || true
  restore_unit_policy "$WORKER_SERVICE" "$worker_was_enabled" "$worker_was_active" || worker_restore_failed=1
  restore_unit_policy "$SERVICE" "$main_was_enabled" "$main_was_active" || main_restore_failed=1
  if (( main_was_active )); then
    for _ in {1..40}; do
      if rollback_main_ready; then rollback_ok=1; break; fi
      sleep 0.25
    done
    (( rollback_ok )) || die "rollback failed to restore previous runtime readiness"
  fi
  (( main_restore_failed == 0 )) || die "rollback failed to restore main service policy"
  (( worker_restore_failed == 0 )) || die "rollback failed to restore privileged worker policy"
  die "update rolled back after failed dual-runtime acceptance"
}

socket_ready() {
  [[ -S "$SOCKET" ]] || return 1
  local owner group mode
  owner="$(stat -Lc '%U' "$SOCKET" 2>/dev/null)" || return 1
  group="$(stat -Lc '%G' "$SOCKET" 2>/dev/null)" || return 1
  mode="$(stat -Lc '%a' "$SOCKET" 2>/dev/null)" || return 1
  getent group "$EXPECTED_SOCKET_GROUP" >/dev/null || return 1
  [[ "$owner" == "root" && "$group" == "$EXPECTED_SOCKET_GROUP" && "$mode" == "660" ]]
}
main_ready() {
  local readiness_body version_body
  systemctl is-active --quiet "$SERVICE" || return 1
  curl -fsS --max-time 2 "${BASE_URL}/api/v1/health" >/dev/null 2>&1 || return 1
  readiness_body="$(curl -fsS --max-time 2 "${BASE_URL}/api/v1/readiness" 2>/dev/null || true)"
  version_body="$(curl -fsS --max-time 2 "${BASE_URL}/api/v1/version" 2>/dev/null || true)"
  grep -Fq '"ready":true' <<<"$readiness_body" && grep -Fq "\"version\":\"$target_version\"" <<<"$version_body"
}

log "switching dual runtime $current_version -> $target_version ($release_id)"
atomic_link "$release_rel" "$CURRENT_LINK"
systemctl reset-failed "$WORKER_SERVICE" "$SERVICE" >/dev/null 2>&1 || true
if ! systemctl enable "$WORKER_SERVICE" >/dev/null; then
  rollback "privileged worker enable failed"
fi
if ! systemctl restart "$WORKER_SERVICE"; then
  rollback "privileged worker restart failed"
fi
worker_ok=0
for _ in {1..24}; do
  if systemctl is-active --quiet "$WORKER_SERVICE" && socket_ready; then worker_ok=1; break; fi
  sleep 0.25
done
(( worker_ok )) || rollback "privileged worker acceptance failed"

if ! systemctl restart "$SERVICE"; then
  rollback "main runtime restart failed"
fi
main_ok=0
for _ in {1..24}; do
  if main_ready; then main_ok=1; break; fi
  sleep 0.25
done
(( main_ok )) || rollback "main runtime acceptance failed"

atomic_link "$old_target" "$PREVIOUS_LINK"
log "update completed; current=$release_rel previous=$old_target"
