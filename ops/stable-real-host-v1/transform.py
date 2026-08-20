from pathlib import Path
import sys

if len(sys.argv) != 3:
    raise SystemExit("usage: transform.py <rc-v7.sh> <stable.sh>")

src = Path(sys.argv[1]).read_text()

def once(old: str, new: str, label: str) -> None:
    global src
    count = src.count(old)
    if count != 1:
        raise SystemExit(f"ERROR: {label}: expected exactly one anchor, found {count}")
    src = src.replace(old, new, 1)

# Exact stable candidate and accepted RC baseline identities.
once('RC_VERSION="1.0.0-rc.1"', 'RC_VERSION="1.0.0"', 'candidate version')
once('RC_COMMIT="77b62d5829a46b1b29698495043146d79f37dc48"',
     'RC_COMMIT="1b364ae88789696bf98537d21544de8a259d086d"', 'candidate commit')
once('BETA_VERSION="1.0.0-beta.1"', 'BETA_VERSION="1.0.0-rc.1"', 'baseline version')
once('BETA_COMMIT="b3b7cd7d3a1985bbe02b392bce5e26d5bf0cf39c"',
     'BETA_COMMIT="77b62d5829a46b1b29698495043146d79f37dc48"', 'baseline commit')
once('PRIOR_RC_COMMIT="2b104ffa69d5f11b1a4de24fe92be95d89422acd"',
     'PRIOR_RC_COMMIT="77b62d5829a46b1b29698495043146d79f37dc48"', 'prior rc commit')
once('PRIOR_RC_AMD64_SHA256="0ecdfd3d44a2d5ba58d2d221527765e4014a0fa4fc62b7e73ac06718fb3a5121"',
     'PRIOR_RC_AMD64_SHA256="dd1bae6364657c1f65a72c63e428f61df58d0030ee85b5320ede6a598a6a6c1d"', 'prior amd64')
once('PRIOR_RC_ARM64_SHA256="232393b745f0b649126a891f262d469a45eac97340856b1ce2952934780dbe74"',
     'PRIOR_RC_ARM64_SHA256="fadd38f5211442073a071a3d87cad35bc1f4f89c0e3466a36861f40dbbf8f54e"', 'prior arm64')
once('RC_AMD64_SHA256="dd1bae6364657c1f65a72c63e428f61df58d0030ee85b5320ede6a598a6a6c1d"',
     'RC_AMD64_SHA256="341f6a49646f92aca72692730ea61278cc03bfc1689d029d7a7ce573554fa735"', 'stable amd64')
once('RC_ARM64_SHA256="fadd38f5211442073a071a3d87cad35bc1f4f89c0e3466a36861f40dbbf8f54e"',
     'RC_ARM64_SHA256="5e6e959f39bd4cb554e902908863c92eb5c697f4d99b55ca97fa4735ec9419fe"', 'stable arm64')

# Stable-specific filesystem/evidence names.
once('BASE="/opt/control-center-rc1-acceptance"', 'BASE="/opt/control-center-stable-acceptance"', 'base path')
once('RC_PACKAGE="$BASE/control-center-1.0.0-rc.1.tar.gz"',
     'RC_PACKAGE="$BASE/control-center-1.0.0.tar.gz"', 'candidate package path')
once('BETA_PACKAGE="$BASE/control-center-accepted-beta.1.tar.gz"',
     'BETA_PACKAGE="$BASE/control-center-accepted-rc.1.tar.gz"', 'baseline package path')
once('RESUME_SCRIPT="/usr/local/sbin/control-center-rc1-acceptance-resume"',
     'RESUME_SCRIPT="/usr/local/sbin/control-center-stable-acceptance-resume"', 'resume script')
once('RESUME_UNIT="/etc/systemd/system/control-center-rc1-acceptance-resume.service"',
     'RESUME_UNIT="/etc/systemd/system/control-center-stable-acceptance-resume.service"', 'resume unit')
once('RESUME_UNIT_NAME="control-center-rc1-acceptance-resume.service"',
     'RESUME_UNIT_NAME="control-center-stable-acceptance-resume.service"', 'resume unit name')

# On any stable acceptance failure, return to the already accepted RC baseline.
old_recovery = '''recover_exact_rc() {
  set +e
  if [[ -f "$PUBLIC_KEY" ]]; then install_test_trust >/dev/null 2>&1 || true; fi
  if [[ -f "$RC_PACKAGE" && -x /usr/local/sbin/control-center-update ]]; then
    CONTROL_CENTER_UPDATE_HEALTH_URL="$BACKEND_URL" /usr/local/sbin/control-center-update --package "$RC_PACKAGE" --allow-downgrade >/dev/null 2>&1 || true
  elif [[ -x "$SOURCE_DIR/install/install.sh" && -f "$SOURCE_DIR/dist/control-center-linux-$GOARCH" ]]; then
    CONTROL_CENTER_BINARY="$SOURCE_DIR/dist/control-center-linux-$GOARCH" CONTROL_CENTER_UPDATE_PUBLIC_KEY="$PUBLIC_KEY" CONTROL_CENTER_ACCEPTANCE_URL="$BACKEND_URL" \
      "$SOURCE_DIR/install/install.sh" --reinstall >/dev/null 2>&1 || true
  fi
  systemctl reset-failed control-center.service >/dev/null 2>&1 || true
  systemctl start control-center.service >/dev/null 2>&1 || true
  set -e
}
'''
new_recovery = '''recover_exact_rc() {
  set +e
  if [[ -f "$PUBLIC_KEY" ]]; then install_test_trust >/dev/null 2>&1 || true; fi
  if [[ -f "$BETA_PACKAGE" && -x /usr/local/sbin/control-center-update ]]; then
    CONTROL_CENTER_UPDATE_HEALTH_URL="$BACKEND_URL" /usr/local/sbin/control-center-update --package "$BETA_PACKAGE" --allow-downgrade >/dev/null 2>&1 || true
  fi
  systemctl reset-failed control-center.service >/dev/null 2>&1 || true
  systemctl start control-center.service >/dev/null 2>&1 || true
  set -e
}
'''
once(old_recovery, new_recovery, 'failure recovery')

# Initial host must be the accepted final RC; then do exactly RC -> stable.
old_preflight = '''  [[ "$(current_version)" == "$RC_VERSION" ]] || die "host is not on the previously tested rc.1"
  [[ "$(current_commit)" == "$PRIOR_RC_COMMIT" ]] || die "host prior rc.1 commit is not the expected source identity"
  printf '%s  %s\n' "$EXPECTED_PRIOR_RC_SHA" /usr/local/lib/control-center/current/control-center | sha256sum -c -
'''
new_preflight = '''  [[ "$(current_version)" == "$BETA_VERSION" ]] || die "host is not on the accepted rc.1 baseline"
  [[ "$(current_commit)" == "$BETA_COMMIT" ]] || die "host accepted rc.1 commit is not the expected source identity"
  printf '%s  %s\n' "$EXPECTED_PRIOR_RC_SHA" /usr/local/lib/control-center/current/control-center | sha256sum -c -
'''
once(old_preflight, new_preflight, 'initial baseline preflight')

old_upgrade = '''  build_exact_candidate
  package_exact_candidate
  package_accepted_beta

  STEP="restore-accepted-beta1"
  log "Restore accepted beta.1 before final rc.1 upgrade regression"
  install_test_trust
  PRODUCT_CHANGED=1
  CONTROL_CENTER_UPDATE_HEALTH_URL="$BACKEND_URL" /usr/local/sbin/control-center-update --package "$BETA_PACKAGE" --allow-downgrade
  wait_ready "$BACKEND_URL" || die "accepted beta.1 did not become ready"
  [[ "$(current_version)" == "$BETA_VERSION" && "$(current_commit)" == "$BETA_COMMIT" ]] || die "accepted beta.1 restore identity mismatch"

  STEP="upgrade-beta1-to-final-rc1"
  log "Upgrade accepted beta.1 to final exact rc.1"
  CONTROL_CENTER_UPDATE_HEALTH_URL="$BACKEND_URL" /usr/local/sbin/control-center-update --package "$RC_PACKAGE"
  wait_ready "$BACKEND_URL" || die "rc.1 did not become ready"
  [[ "$(current_version)" == "$RC_VERSION" && "$(current_commit)" == "$RC_COMMIT" ]] || die "installed rc.1 identity mismatch"
  printf '%s  %s\n' "$EXPECTED_RC_SHA" /usr/local/lib/control-center/current/control-center | sha256sum -c -
  BETA_UPGRADE="passed"
'''
new_upgrade = '''  build_exact_candidate
  package_exact_candidate
  package_accepted_beta

  STEP="upgrade-accepted-rc1-to-stable"
  log "Upgrade accepted rc.1 to exact stable 1.0.0"
  install_test_trust
  PRODUCT_CHANGED=1
  CONTROL_CENTER_UPDATE_HEALTH_URL="$BACKEND_URL" /usr/local/sbin/control-center-update --package "$RC_PACKAGE"
  wait_ready "$BACKEND_URL" || die "stable 1.0.0 did not become ready"
  [[ "$(current_version)" == "$RC_VERSION" && "$(current_commit)" == "$RC_COMMIT" ]] || die "installed stable identity mismatch"
  printf '%s  %s\n' "$EXPECTED_RC_SHA" /usr/local/lib/control-center/current/control-center | sha256sum -c -
  BETA_UPGRADE="passed"
'''
once(old_upgrade, new_upgrade, 'baseline to stable upgrade')

# Disable historical interrupted-RC continuation path; stable uses initial + reboot resume only.
once('phase_continue_after_upgrade() {\n',
     'phase_continue_after_upgrade() {\n  die "continue-after-upgrade mode is not supported by stable acceptance"\n  return 1\n',
     'disable historical continue mode')

# Stable source validation and synthetic update contract.
src = src.replace('scripts/rc1-update-acceptance.sh', 'scripts/stable-update-acceptance.sh')
src = src.replace('package_accepted_beta', 'package_accepted_baseline')
src = src.replace('recover_exact_rc', 'recover_accepted_baseline')
src = src.replace('BETA_UPGRADE', 'BASELINE_UPGRADE')
src = src.replace('RC_UPDATE_ROLLBACK', 'STABLE_UPDATE_ROLLBACK')
src = src.replace('beta_upgrade=', 'baseline_upgrade=')
src = src.replace('rc_update_rollback=', 'stable_update_rollback=')

# Human-readable evidence labels.
replacements = {
    'Fetch and build exact rc.1 with pinned Go $GO_VERSION': 'Fetch and build exact stable 1.0.0 with pinned Go $GO_VERSION',
    'Package exact signed rc.1 candidate': 'Package exact signed stable 1.0.0 candidate',
    'Package preserved accepted beta.1 for exact upgrade-path regression': 'Package preserved accepted rc.1 baseline for recovery',
    'STEP="package-accepted-beta1"': 'STEP="package-accepted-rc1"',
    'state changed during beta restore/final rc upgrade/security acceptance': 'state changed during stable upgrade/security acceptance',
    'secrets changed during beta restore/final rc upgrade/security acceptance': 'secrets changed during stable upgrade/security acceptance',
    'Intentional reboot for rc.1 boot acceptance; resume unit is armed': 'Intentional reboot for stable 1.0.0 boot acceptance; resume unit is armed',
    'current rc.1 backend is not ready': 'current stable backend is not ready',
    'Resume preflight from already installed exact rc.1': 'Resume preflight from already installed exact stable 1.0.0',
    'current version is not rc.1': 'current version is not stable 1.0.0',
    'current rc.1 commit mismatch': 'current stable commit mismatch',
    'accepted beta.1 previous release is unavailable': 'accepted rc.1 previous release is unavailable',
    'previous release is not accepted beta.1': 'previous release is not accepted rc.1',
    'previous beta.1 source identity mismatch': 'previous rc.1 source identity mismatch',
    'Signed rc.2 forward update and broken rc.3 rollback regression': 'Signed 1.0.1 forward update and broken 1.0.2 rollback regression',
    'STEP="rc-forward-update-broken-rollback"': 'STEP="stable-forward-update-broken-rollback"',
    'STEP="restore-exact-rc1"': 'STEP="restore-exact-stable"',
    'Restore exact rc.1 after synthetic update tests': 'Restore exact stable 1.0.0 after synthetic update tests',
    'exact rc.1 restore not ready': 'exact stable restore not ready',
    'exact rc.1 restore identity mismatch': 'exact stable restore identity mismatch',
    'Repair and reinstall exact rc.1': 'Repair and reinstall exact stable 1.0.0',
    'rc.1 not ready after repair/reinstall': 'stable 1.0.0 not ready after repair/reinstall',
    'rc.1 not ready after preserve-state reinstall': 'stable 1.0.0 not ready after preserve-state reinstall',
    'rc.1 identity changed across reboot': 'stable identity changed across reboot',
    'CONTROL CENTER RC1 REAL-HOST ACCEPTANCE': 'CONTROL CENTER 1.0.0 STABLE REAL-HOST ACCEPTANCE',
    'logger -t control-center-rc1-acceptance "RC1 real-host acceptance PASSED commit=$RC_COMMIT report=${REPORT_BRANCH:-unknown}"':
        'logger -t control-center-stable-acceptance "Stable 1.0.0 real-host acceptance PASSED commit=$RC_COMMIT report=${REPORT_BRANCH:-unknown}"',
    '=== RC1 REAL-HOST ACCEPTANCE PASSED ===': '=== CONTROL CENTER 1.0.0 STABLE REAL-HOST ACCEPTANCE PASSED ===',
}
for old, new in replacements.items():
    if old not in src:
        raise SystemExit(f"ERROR: missing text anchor: {old}")
    src = src.replace(old, new)

# Diagnostics branch name is part of the externally visible evidence contract.
once('report_branch="reports/$HOST_SAFE/${START_TS}-rc1"',
     'report_branch="reports/$HOST_SAFE/${START_TS}-stable-1.0.0"', 'diagnostics branch suffix')

# Guardrails: no stale executable path or old work directory may survive.
for forbidden in (
    '/opt/control-center-rc1-acceptance',
    'control-center-rc1-acceptance-resume',
    'scripts/rc1-update-acceptance.sh',
    '1.0.0-beta.1',
    'b3b7cd7d3a1985bbe02b392bce5e26d5bf0cf39c',
):
    if forbidden in src:
        raise SystemExit(f"ERROR: stale RC/beta anchor remains: {forbidden}")

Path(sys.argv[2]).write_text(src)
