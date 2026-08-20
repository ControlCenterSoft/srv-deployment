#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

[[ $EUID -eq 0 ]] || { printf 'ERROR: rc.1 resume v6 must run as root\n' >&2; exit 1; }

V5_LAUNCHER_COMMIT="3a0cfe12fe2bad5c0941808bdcec3988fba7a4a8"
V5_LAUNCHER_URL="https://raw.githubusercontent.com/ControlCenterSoft/srv-deployment/${V5_LAUNCHER_COMMIT}/ops/rc1-real-host-acceptance-v5/run-verified.sh"
V5_LAUNCHER_SHA256="9a4d0982475b12ce089a05eba200b3c408fcaa9fbb7e9ee19805259856fa66c2"
V5_SCRIPT_SHA256="2b470e04973851f79388531fbb30818c1cecc5a8f919b02a1b42adb11804b1e2"
V6_SCRIPT_SHA256="b845558e4172ab4e82fd5ad85dfce88377f767e5bfef16dc9b9f1b48255a2ae9"
WORK="$(mktemp -d /tmp/control-center-rc1-resume-v6-launch.XXXXXX)"
trap 'rm -rf -- "$WORK"' EXIT

curl -fsSL "$V5_LAUNCHER_URL" -o "$WORK/v5-launcher.sh"
printf '%s  %s\n' "$V5_LAUNCHER_SHA256" "$WORK/v5-launcher.sh" | sha256sum -c -

# Convert the immutable v5 launcher into a builder only: it must create exact
# v5 but must not execute it. The builder output is verified again below.
python3 - "$WORK/v5-launcher.sh" "$WORK/v5-builder.sh" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]).read_text()
needle='exec bash "$WORK/v5.sh"\n'
if src.count(needle) != 1:
    raise SystemExit('ERROR: immutable v5 launcher final exec contract did not match')
src=src.replace(needle, 'cp "$WORK/v5.sh" "$OUTPUT_V5"\n', 1)
Path(sys.argv[2]).write_text(src)
PY
chmod 0700 "$WORK/v5-builder.sh"
OUTPUT_V5="$WORK/v5.sh" bash "$WORK/v5-builder.sh"
printf '%s  %s\n' "$V5_SCRIPT_SHA256" "$WORK/v5.sh" | sha256sum -c -

python3 - "$WORK/v5.sh" "$WORK/v6.sh" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]).read_text()

# Fix nounset bug: Bash expands $label before the same local command assigns it.
old='  local label="$1" work="$BASE/api-$label"\n'
new='  local label="$1"\n  local work="$BASE/api-$label"\n'
if src.count(old) != 1:
    raise SystemExit('ERROR: v5 api_security_regression contract did not match')
src=src.replace(old,new,1)

# Persist already-passed pre-reboot gates across the reboot process boundary.
old='STATE_HASH_BEFORE=$STATE_HASH_BEFORE\nSECRETS_HASH_BEFORE=$SECRETS_HASH_BEFORE\nPRODUCT_CHANGED=1\n'
new='STATE_HASH_BEFORE=$STATE_HASH_BEFORE\nSECRETS_HASH_BEFORE=$SECRETS_HASH_BEFORE\nBETA_UPGRADE=$BETA_UPGRADE\nPRE_REBOOT_AUTH=$PRE_REBOOT_AUTH\nPRODUCT_CHANGED=1\n'
if src.count(old) != 1:
    raise SystemExit('ERROR: v5 state persistence contract did not match')
src=src.replace(old,new,1)

# An ERR trap does not catch every set -u termination. Add an EXIT fallback,
# while preserving the intentional reboot handoff.
old='FAILURE_ACTIVE="0"\n'
if src.count(old) != 1:
    raise SystemExit('ERROR: v5 failure state contract did not match')
src=src.replace(old, old+'REBOOT_HANDOFF="0"\n',1)
old="trap 'on_error $? $LINENO' ERR\n\nphase_initial() {\n"
new="""on_exit() {
  local rc="$?"
  if [[ "$rc" -ne 0 && "${FAILURE_ACTIVE:-0}" == 0 ]]; then
    # During the intentional reboot the shell may be terminated by shutdown.
    # The state file + installed resume unit are the handoff and must survive.
    if [[ "${REBOOT_HANDOFF:-0}" == 1 && -f "$STATE_FILE" ]]; then
      return 0
    fi
    on_error "$rc" "${BASH_LINENO[0]:-0}"
  fi
}
trap 'on_error $? $LINENO' ERR
trap 'on_exit' EXIT

phase_initial() {
"""
if src.count(old) != 1:
    raise SystemExit('ERROR: v5 trap contract did not match')
src=src.replace(old,new,1)

old='''  log "Intentional reboot for rc.1 boot acceptance; resume unit is armed"\n  systemctl reboot\n'''
new='''  log "Intentional reboot for rc.1 boot acceptance; resume unit is armed"\n  REBOOT_HANDOFF=1\n  systemctl reboot\n'''
if src.count(old) != 1:
    raise SystemExit(f'ERROR: expected exactly one v5 reboot handoff site, found {src.count(old)}')
src=src.replace(old,new,1)

continue_func=r'''phase_continue_after_upgrade() {
  START_TS="$(date -u +%Y%m%dT%H%M%SZ)"
  HOST_SAFE="$(hostname | tr -cd 'A-Za-z0-9._-' | head -c 80)"
  PUBLIC_IP="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  [[ -n "$PUBLIC_IP" ]] || PUBLIC_IP="$(hostname -I | awk '{print $1}')"
  PANEL_URL="http://$PUBLIC_IP:8876"
  ensure_dependencies
  setup_arch
  load_backend_url
  wait_ready "$BACKEND_URL" || die "current rc.1 backend is not ready"
  systemctl is-active --quiet nginx.service || die "test HTTP ingress nginx is not active"

  STEP="resume-preflight-after-upgrade"
  log "Resume preflight from already installed exact rc.1"
  [[ "$(current_version)" == "$RC_VERSION" ]] || die "current version is not rc.1"
  [[ "$(current_commit)" == "$RC_COMMIT" ]] || die "current rc.1 commit mismatch"
  printf '%s  %s\n' "$EXPECTED_RC_SHA" /usr/local/lib/control-center/current/control-center | sha256sum -c -

  local previous_target="$(readlink /usr/local/lib/control-center/previous 2>/dev/null || true)"
  [[ -n "$previous_target" && -x "/usr/local/lib/control-center/$previous_target/control-center" ]] || die "accepted beta.1 previous release is unavailable"
  [[ "$(/usr/local/lib/control-center/$previous_target/control-center build-info --field version)" == "$BETA_VERSION" ]] || die "previous release is not accepted beta.1"
  [[ "$(/usr/local/lib/control-center/$previous_target/control-center build-info --field commit)" == "$BETA_COMMIT" ]] || die "previous beta.1 source identity mismatch"

  # Independently recorded in the immediately preceding beta.1/v4 evidence.
  STATE_HASH_BEFORE="373be9ea853f43fb843b44974a3b767ba84f498bddab53a0a8d9b59a76910d2e"
  SECRETS_HASH_BEFORE="b22b30944c85089515e699b684f0e446788e1719e16e8e7d16e4cd789182452c"
  [[ "$(safe_hash /var/lib/control-center/state.json)" == "$STATE_HASH_BEFORE" ]] || die "state hash differs from pre-upgrade beta.1 evidence"
  [[ "$(safe_hash /var/lib/control-center/secrets.json)" == "$SECRETS_HASH_BEFORE" ]] || die "secrets hash differs from pre-upgrade beta.1 evidence"

  [[ -f "$HAD_TRUST_FILE" ]] || die "original trust marker missing after interrupted v5"
  [[ "$(cat "$HAD_TRUST_FILE")" == 1 ]] || die "unexpected original trust marker"
  [[ -f "$ORIGINAL_TRUST" ]] || die "original update trust backup missing"
  [[ -s "$PRIVATE_KEY" && -s "$PUBLIC_KEY" ]] || die "ephemeral signing trust from v5 is incomplete"
  [[ -f "$TRUST_KEY" ]] || die "installed update trust missing"
  cmp -s "$PUBLIC_KEY" "$TRUST_KEY" || die "installed trust is not the v5 ephemeral public key"
  openssl pkey -in "$PRIVATE_KEY" -pubout 2>/dev/null | cmp - "$PUBLIC_KEY" || die "private/public signing key mismatch"

  [[ -d "$SOURCE_DIR/.git" ]] || die "v5 exact source checkout missing"
  [[ "$(git -C "$SOURCE_DIR" rev-parse HEAD)" == "$RC_COMMIT" ]] || die "v5 source checkout commit mismatch"
  [[ -x "$SOURCE_DIR/scripts/rc1-update-acceptance.sh" ]] || die "rc update acceptance script is not executable"
  printf '%s  %s\n' "$EXPECTED_RC_SHA" "$SOURCE_DIR/dist/control-center-linux-$GOARCH" | sha256sum -c -
  [[ -f "$RC_PACKAGE" ]] || die "signed rc.1 package from v5 missing"
  local package_check="$BASE/resume-package-check"
  rm -rf "$package_check"; mkdir -p "$package_check"
  tar -xzf "$RC_PACKAGE" -C "$package_check"
  "$SOURCE_DIR/dist/control-center-linux-$GOARCH" verify-release \
    --manifest "$package_check/manifest.json" --signature "$package_check/manifest.sig" --public-key "$PUBLIC_KEY" \
    --artifact "$package_check/control-center" --field release-id >/dev/null
  rm -rf "$package_check"

  rm -f "$STATE_FILE"
  remove_resume_unit
  rm -rf -- "$BASE"/api-* 2>/dev/null || true
  OLD_BOOT_ID="$(cat /proc/sys/kernel/random/boot_id)"
  BETA_UPGRADE="passed"
  PRODUCT_CHANGED=1

  STEP="pre-reboot-auth-security"
  log "Pre-reboot browser/security regression (resumed)"
  api_security_regression pre-reboot
  PRE_REBOOT_AUTH="passed"
  [[ "$(safe_hash /var/lib/control-center/state.json)" == "$STATE_HASH_BEFORE" ]] || die "state changed during resumed pre-reboot acceptance"
  [[ "$(safe_hash /var/lib/control-center/secrets.json)" == "$SECRETS_HASH_BEFORE" ]] || die "secrets changed during resumed pre-reboot acceptance"

  STEP="schedule-reboot-resume"
  write_state_file
  install_resume_unit
  sync
  log "Intentional reboot for rc.1 boot acceptance; resume unit is armed"
  REBOOT_HANDOFF=1
  systemctl reboot
  sleep 20
  exit 0
}

'''
needle='phase_resume() {\n'
if src.count(needle) != 1:
    raise SystemExit('ERROR: v5 phase_resume contract did not match')
src=src.replace(needle,continue_func+needle,1)

old='''if [[ ${1:-} == "--resume" ]]; then\n  phase_resume\nelse\n'''
new='''if [[ ${1:-} == "--resume" ]]; then\n  phase_resume\nelif [[ ${1:-} == "--continue-after-upgrade" ]]; then\n  phase_continue_after_upgrade\nelse\n'''
if src.count(old) != 1:
    raise SystemExit('ERROR: v5 dispatch contract did not match')
src=src.replace(old,new,1)
Path(sys.argv[2]).write_text(src)
PY

printf '%s  %s\n' "$V6_SCRIPT_SHA256" "$WORK/v6.sh" | sha256sum -c -
bash -n "$WORK/v6.sh"
chmod 0700 "$WORK/v6.sh"

if [[ ${RC1_V6_BUILD_ONLY:-0} == 1 ]]; then
  printf 'V6_BUILD_ONLY=PASSED\nV6_SHA256=%s\n' "$V6_SCRIPT_SHA256"
  exit 0
fi

exec bash "$WORK/v6.sh" --continue-after-upgrade
