#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

BUILD_ONLY="${STABLE_ACCEPTANCE_BUILD_ONLY:-0}"
if [[ "$BUILD_ONLY" != 1 && $EUID -ne 0 ]]; then
  echo 'ERROR: stable 1.0.0 real-host acceptance must run as root' >&2
  exit 1
fi

RC_V7_COMMIT="fe579e3f38e18bf1fc56a93699489b762206427d"
RC_V7_URL="https://raw.githubusercontent.com/ControlCenterSoft/srv-deployment/${RC_V7_COMMIT}/ops/rc1-real-host-acceptance-v7/run-verified.sh"
RC_V7_LAUNCHER_GIT_BLOB_SHA1="65625a24659540df4226cf60134365f18b2917cd"
EXPECTED_STABLE_SCRIPT_SHA256=""
WORK="$(mktemp -d /tmp/control-center-stable-v1-launch.XXXXXX)"
trap 'rm -rf -- "$WORK"' EXIT

curl -fsSL "$RC_V7_URL" -o "$WORK/rc-v7-launcher.sh"
size="$(wc -c < "$WORK/rc-v7-launcher.sh" | tr -d ' ')"
actual_blob="$({ printf 'blob %s\0' "$size"; cat "$WORK/rc-v7-launcher.sh"; } | sha1sum | awk '{print $1}')"
[[ "$actual_blob" == "$RC_V7_LAUNCHER_GIT_BLOB_SHA1" ]] || {
  echo "ERROR: immutable rc v7 launcher blob mismatch: $actual_blob" >&2
  exit 1
}

RC1_V7_BUILD_ONLY=1 OUTPUT_V7="$WORK/rc-v7.sh" bash "$WORK/rc-v7-launcher.sh"

python3 - "$WORK/rc-v7.sh" "$WORK/stable-v1.sh" <<'PY'
from pathlib import Path
import sys

src = Path(sys.argv[1]).read_text()

def one(old, new, label):
    global src
    count = src.count(old)
    if count != 1:
        raise SystemExit(f"ERROR: {label} anchor count={count}")
    src = src.replace(old, new, 1)

# Stable candidate identity. Runtime source semantics remain inherited from accepted rc.1.
one('RC_VERSION="1.0.0-rc.1"', 'RC_VERSION="1.0.0"', 'candidate version')
one('RC_COMMIT="77b62d5829a46b1b29698495043146d79f37dc48"', 'RC_COMMIT="1b364ae88789696bf98537d21544de8a259d086d"', 'candidate commit')
one('RC_AMD64_SHA256="dd1bae6364657c1f65a72c63e428f61df58d0030ee85b5320ede6a598a6a6c1d"', 'RC_AMD64_SHA256="341f6a49646f92aca72692730ea61278cc03bfc1689d029d7a7ce573554fa735"', 'candidate amd64')
one('RC_ARM64_SHA256="fadd38f5211442073a071a3d87cad35bc1f4f89c0e3466a36861f40dbbf8f54e"', 'RC_ARM64_SHA256="5e6e959f39bd4cb554e902908863c92eb5c697f4d99b55ca97fa4735ec9419fe"', 'candidate arm64')

# The accepted upgrade source is final rc.1, not beta.1.
one('BETA_VERSION="1.0.0-beta.1"', 'BETA_VERSION="1.0.0-rc.1"', 'accepted source version')
one('BETA_COMMIT="b3b7cd7d3a1985bbe02b392bce5e26d5bf0cf39c"', 'BETA_COMMIT="77b62d5829a46b1b29698495043146d79f37dc48"', 'accepted source commit')
one('PRIOR_RC_COMMIT="2b104ffa69d5f11b1a4de24fe92be95d89422acd"', 'PRIOR_RC_COMMIT="77b62d5829a46b1b29698495043146d79f37dc48"', 'prior rc commit')
one('PRIOR_RC_AMD64_SHA256="0ecdfd3d44a2d5ba58d2d221527765e4014a0fa4fc62b7e73ac06718fb3a5121"', 'PRIOR_RC_AMD64_SHA256="dd1bae6364657c1f65a72c63e428f61df58d0030ee85b5320ede6a598a6a6c1d"', 'prior rc amd64')
one('PRIOR_RC_ARM64_SHA256="232393b745f0b649126a891f262d469a45eac97340856b1ce2952934780dbe74"', 'PRIOR_RC_ARM64_SHA256="fadd38f5211442073a071a3d87cad35bc1f4f89c0e3466a36861f40dbbf8f54e"', 'prior rc arm64')

# Keep stable acceptance evidence separate from rc.1 evidence.
if '/opt/control-center-rc1-acceptance' not in src:
    raise SystemExit('ERROR: rc acceptance base path missing')
src = src.replace('/opt/control-center-rc1-acceptance', '/opt/control-center-stable-acceptance')
src = src.replace('control-center-rc1-acceptance-resume.service', 'control-center-stable-acceptance-resume.service')
one('RC_PACKAGE="$BASE/control-center-1.0.0-rc.1.tar.gz"', 'RC_PACKAGE="$BASE/control-center-1.0.0.tar.gz"', 'stable package path')
one('BETA_PACKAGE="$BASE/control-center-accepted-beta.1.tar.gz"', 'BETA_PACKAGE="$BASE/control-center-accepted-rc.1.tar.gz"', 'accepted rc package path')

# Preflight must prove that the host is still on the accepted final rc.1.
old_preflight = '''  [[ "$(current_version)" == "$RC_VERSION" ]] || die "host is not on the previously tested rc.1"\n  [[ "$(current_commit)" == "$PRIOR_RC_COMMIT" ]] || die "host prior rc.1 commit is not the expected source identity"\n  printf '%s  %s\\n' "$EXPECTED_PRIOR_RC_SHA" /usr/local/lib/control-center/current/control-center | sha256sum -c -\n  systemctl is-active --quiet nginx.service || die "test HTTP ingress nginx is not active"\n'''
new_preflight = '''  [[ "$(current_version)" == "$BETA_VERSION" ]] || die "host is not on accepted rc.1"\n  [[ "$(current_commit)" == "$BETA_COMMIT" ]] || die "host accepted rc.1 commit is not the expected source identity"\n  printf '%s  %s\\n' "$EXPECTED_PRIOR_RC_SHA" /usr/local/lib/control-center/current/control-center | sha256sum -c -\n  systemctl is-active --quiet nginx.service || die "test HTTP ingress nginx is not active"\n'''
one(old_preflight, new_preflight, 'accepted rc preflight')

# Preserve/package accepted rc.1, but do not perform a redundant same-version restore.
old_upgrade = '''  build_exact_candidate\n  package_exact_candidate\n  package_accepted_beta\n\n  STEP="restore-accepted-beta1"\n  log "Restore accepted beta.1 before final rc.1 upgrade regression"\n  install_test_trust\n  PRODUCT_CHANGED=1\n  CONTROL_CENTER_UPDATE_HEALTH_URL="$BACKEND_URL" /usr/local/sbin/control-center-update --package "$BETA_PACKAGE" --allow-downgrade\n  wait_ready "$BACKEND_URL" || die "accepted beta.1 did not become ready"\n  [[ "$(current_version)" == "$BETA_VERSION" && "$(current_commit)" == "$BETA_COMMIT" ]] || die "accepted beta.1 restore identity mismatch"\n\n  STEP="upgrade-beta1-to-final-rc1"\n  log "Upgrade accepted beta.1 to final exact rc.1"\n  CONTROL_CENTER_UPDATE_HEALTH_URL="$BACKEND_URL" /usr/local/sbin/control-center-update --package "$RC_PACKAGE"\n'''
new_upgrade = '''  build_exact_candidate\n  package_exact_candidate\n  package_accepted_beta\n\n  STEP="upgrade-accepted-rc1-to-stable"\n  log "Upgrade accepted rc.1 to final exact 1.0.0"\n  install_test_trust\n  PRODUCT_CHANGED=1\n  CONTROL_CENTER_UPDATE_HEALTH_URL="$BACKEND_URL" /usr/local/sbin/control-center-update --package "$RC_PACKAGE"\n'''
one(old_upgrade, new_upgrade, 'stable upgrade block')

# Stable synthetic lifecycle is 1.0.1 -> broken 1.0.2 -> rollback.
count = src.count('scripts/rc1-update-acceptance.sh')
if count != 1:
    raise SystemExit(f'ERROR: rc update acceptance path count={count}')
src = src.replace('scripts/rc1-update-acceptance.sh', 'scripts/stable-update-acceptance.sh')
src = src.replace('Signed rc.2 forward update and broken rc.3 rollback regression', 'Signed 1.0.1 forward update and broken 1.0.2 rollback regression')
src = src.replace('rc-forward-update-broken-rollback', 'stable-forward-update-broken-rollback')
src = src.replace('state changed during beta restore/final rc upgrade/security acceptance', 'state changed during rc.1 to stable upgrade/security acceptance')
src = src.replace('secrets changed during beta restore/final rc upgrade/security acceptance', 'secrets changed during rc.1 to stable upgrade/security acceptance')

# Evidence labels only; do not alter product semantics.
src = src.replace('=== RC1 REAL-HOST ACCEPTANCE PASSED ===', '=== STABLE 1.0.0 REAL-HOST ACCEPTANCE PASSED ===')
src = src.replace('rc1-real-host-acceptance', 'stable-1.0.0-real-host-acceptance')
src = src.replace('-rc1', '-stable100')

Path(sys.argv[2]).write_text(src)
PY

bash -n "$WORK/stable-v1.sh"
actual_stable_sha="$(sha256sum "$WORK/stable-v1.sh" | awk '{print $1}')"
printf 'STABLE_SCRIPT_SHA256=%s\n' "$actual_stable_sha"

if [[ "$BUILD_ONLY" == 1 ]]; then
  cp "$WORK/stable-v1.sh" "${OUTPUT_STABLE:?OUTPUT_STABLE required in build-only mode}"
  echo 'STABLE_BUILD_ONLY=PASSED'
  exit 0
fi

[[ -n "$EXPECTED_STABLE_SCRIPT_SHA256" ]] || {
  echo 'ERROR: production execution is disabled until stable orchestrator SHA is pinned' >&2
  exit 1
}
[[ "$actual_stable_sha" == "$EXPECTED_STABLE_SCRIPT_SHA256" ]] || {
  echo "ERROR: stable orchestrator SHA mismatch: $actual_stable_sha" >&2
  exit 1
}

exec bash "$WORK/stable-v1.sh"
