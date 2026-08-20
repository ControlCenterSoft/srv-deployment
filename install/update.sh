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

INSTALL_ROOT="/usr/local/lib/control-center"
RELEASES_DIR="$INSTALL_ROOT/releases"
STAGING_DIR="$INSTALL_ROOT/staging"
CURRENT_LINK="$INSTALL_ROOT/current"
PREVIOUS_LINK="$INSTALL_ROOT/previous"
CURRENT_BIN="$CURRENT_LINK/control-center"
SERVICE="control-center.service"
BASE_URL="${CONTROL_CENTER_UPDATE_HEALTH_URL:-http://127.0.0.1:8876}"

log() { printf '[control-center-update] %s\n' "$*"; }
die() { printf '[control-center-update] ERROR: %s\n' "$*" >&2; exit 1; }
atomic_link() {
  local target="$1" link="$2" tmp="${2}.new.$$"
  rm -f -- "$tmp"
  ln -s -- "$target" "$tmp"
  mv -Tf -- "$tmp" "$link"
}

[[ $EUID -eq 0 ]] || die "update must run as root"
[[ -n "$PACKAGE" && -f "$PACKAGE" ]] || die "release package is required"
[[ -f "$PUBLIC_KEY" ]] || die "trusted update public key not found: $PUBLIC_KEY"
[[ -x "$CURRENT_BIN" ]] || die "trusted current runtime not found: $CURRENT_BIN"
command -v tar >/dev/null || die "tar is required"
command -v systemctl >/dev/null || die "systemd is required"
command -v curl >/dev/null || die "curl is required"
[[ -L "$CURRENT_LINK" ]] || die "current release link is missing; install beta update foundation first"

entries="$(tar -tzf "$PACKAGE")" || die "unable to list release package"
expected=$'manifest.json\nmanifest.sig\ncontrol-center'
[[ "$entries" == "$expected" ]] || die "release package contains unexpected entries"

install -d -o root -g root -m 0755 "$RELEASES_DIR" "$STAGING_DIR"
stage="$(mktemp -d "$STAGING_DIR/update.XXXXXX")"
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT
tar --no-same-owner --no-same-permissions -xzf "$PACKAGE" -C "$stage"
for f in manifest.json manifest.sig control-center; do
  [[ -f "$stage/$f" && ! -L "$stage/$f" ]] || die "invalid staged entry: $f"
done
chmod 0644 "$stage/manifest.json" "$stage/manifest.sig"
chmod 0755 "$stage/control-center"

release_id="$("$CURRENT_BIN" verify-release --manifest "$stage/manifest.json" --signature "$stage/manifest.sig" --public-key "$PUBLIC_KEY" --artifact "$stage/control-center" --field release-id)" || die "release verification failed"
target_version="$("$CURRENT_BIN" verify-release --manifest "$stage/manifest.json" --signature "$stage/manifest.sig" --public-key "$PUBLIC_KEY" --artifact "$stage/control-center" --field version)" || die "release verification failed"
target_commit="$("$CURRENT_BIN" verify-release --manifest "$stage/manifest.json" --signature "$stage/manifest.sig" --public-key "$PUBLIC_KEY" --artifact "$stage/control-center" --field commit)" || die "release verification failed"

candidate_version="$("$stage/control-center" build-info --field version)" || die "verified candidate cannot report version"
candidate_commit="$("$stage/control-center" build-info --field commit)" || die "verified candidate cannot report commit"
[[ "$candidate_version" == "$target_version" ]] || die "candidate version does not match signed manifest"
[[ "$candidate_commit" == "$target_commit" ]] || die "candidate commit does not match signed manifest"

current_version="$("$CURRENT_BIN" build-info --field version)"
comparison="$("$CURRENT_BIN" compare-version --current "$current_version" --target "$target_version")" || die "unable to compare release versions"
if (( comparison >= 0 && ! ALLOW_DOWNGRADE )); then
  die "target $target_version is not newer than current $current_version; use --allow-downgrade only for an explicit controlled rollback"
fi

release_dir="$RELEASES_DIR/$release_id"
release_rel="releases/$release_id"
if [[ -e "$release_dir" ]]; then
  [[ -d "$release_dir" && -f "$release_dir/control-center" && ! -L "$release_dir/control-center" ]] || die "existing release directory is invalid"
  cmp -s -- "$stage/control-center" "$release_dir/control-center" || die "existing release id has different artifact bytes"
else
  tmp_release="$(mktemp -d "$RELEASES_DIR/.release.XXXXXX")"
  install -m 0555 "$stage/control-center" "$tmp_release/control-center"
  install -m 0444 "$stage/manifest.json" "$tmp_release/manifest.json"
  install -m 0444 "$stage/manifest.sig" "$tmp_release/manifest.sig"
  chmod 0555 "$tmp_release"
  mv -- "$tmp_release" "$release_dir"
fi

old_target="$(readlink "$CURRENT_LINK")"
[[ -n "$old_target" ]] || die "current release target is empty"
log "switching $current_version -> $target_version ($release_id)"
atomic_link "$release_rel" "$CURRENT_LINK"

post_acceptance() {
  local version_body readiness_body
  for _ in {1..24}; do
    if systemctl is-active --quiet "$SERVICE" && \
       curl -fsS --max-time 2 ${BASE_URL}/api/v1/health >/dev/null 2>&1; then
      readiness_body="$(curl -fsS --max-time 2 ${BASE_URL}/api/v1/readiness 2>/dev/null || true)"
      version_body="$(curl -fsS --max-time 2 ${BASE_URL}/api/v1/version 2>/dev/null || true)"
      if grep -Fq '"ready":true' <<<"$readiness_body" && grep -Fq "\"version\":\"$target_version\"" <<<"$version_body"; then
        return 0
      fi
    fi
    sleep 0.25
  done
  return 1
}

if ! systemctl restart "$SERVICE" || ! post_acceptance; then
  log "post-update acceptance failed; rolling back to $old_target"
  atomic_link "$old_target" "$CURRENT_LINK"
  systemctl restart "$SERVICE" >/dev/null 2>&1 || true
  for _ in {1..20}; do
    if curl -fsS --max-time 2 ${BASE_URL}/api/v1/health >/dev/null 2>&1; then break; fi
    sleep 0.25
  done
  die "update rolled back after failed post-update acceptance"
fi

atomic_link "$old_target" "$PREVIOUS_LINK"
log "update completed; current=$release_rel previous=$old_target"
