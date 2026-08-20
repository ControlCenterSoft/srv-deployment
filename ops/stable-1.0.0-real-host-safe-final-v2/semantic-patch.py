from pathlib import Path
import sys

if len(sys.argv) != 3:
    raise SystemExit('usage: semantic-patch.py <safe-v1.sh> <safe-v2.sh>')

src = Path(sys.argv[1]).read_text()

# Identifier normalization. These are evidence/orchestrator names only; release logic is unchanged.
identifier_replacements = {
    'BETA_VERSION': 'BASELINE_VERSION',
    'BETA_COMMIT': 'BASELINE_COMMIT',
    'BETA_PACKAGE': 'BASELINE_PACKAGE',
    'BETA_UPGRADE': 'BASELINE_UPGRADE',
    'RC_UPDATE_ROLLBACK': 'STABLE_UPDATE_ROLLBACK',
    'package_accepted_beta': 'package_accepted_rc_baseline',
}
for old, new in identifier_replacements.items():
    if old not in src:
        raise SystemExit(f'ERROR: missing identifier anchor {old}')
    src = src.replace(old, new)

# Exact human/evidence labels. Require each original text exactly once to fail closed on drift.
replacements = {
    'PRIVATE_KEY="$BASE/rc1-test-private.pem"': 'PRIVATE_KEY="$BASE/stable-test-private.pem"',
    'PUBLIC_KEY="$BASE/rc1-test-public.pem"': 'PUBLIC_KEY="$BASE/stable-test-public.pem"',
    'RESUME_SCRIPT="/usr/local/sbin/control-center-stable100-acceptance-resume"': 'RESUME_SCRIPT="/usr/local/sbin/control-center-stable-1.0.0-acceptance-resume"',
    "ERROR: rc.1 real-host acceptance must run as root": "ERROR: stable 1.0.0 real-host acceptance must run as root",
    'Fetch and build exact rc.1 with pinned Go $GO_VERSION': 'Fetch and build exact stable 1.0.0 with pinned Go $GO_VERSION',
    'Package exact signed rc.1 candidate': 'Package exact signed stable 1.0.0 candidate',
    'STEP="package-accepted-beta1"': 'STEP="package-accepted-rc1"',
    'Package preserved accepted beta.1 for exact upgrade-path regression': 'Package preserved accepted rc.1 baseline for recovery',
    'local d bin="" v c built_at check="$BASE/beta-package-check"': 'local d bin="" v c built_at check="$BASE/rc-baseline-package-check"',
    'accepted beta.1 release binary is not preserved on host': 'accepted rc.1 release binary is not preserved on host',
    'accepted beta.1 built-at is not canonical RFC3339 UTC': 'accepted rc.1 built-at is not canonical RFC3339 UTC',
    'rc1-deliberately-wrong-current-password': 'stable-deliberately-wrong-current-password',
    'rc1-deliberately-unused-new-password': 'stable-deliberately-unused-new-password',
    'rc1-rate-test-${START_TS}': 'stable-rate-test-${START_TS}',
    'Description=Control Center rc.1 acceptance resume after reboot': 'Description=Control Center 1.0.0 stable acceptance resume after reboot',
    'CONTROL CENTER RC1 REAL-HOST ACCEPTANCE': 'CONTROL CENTER 1.0.0 STABLE REAL-HOST ACCEPTANCE',
    'beta_upgrade=$BASELINE_UPGRADE': 'baseline_upgrade=$BASELINE_UPGRADE',
    'rc_update_rollback=$STABLE_UPDATE_ROLLBACK': 'stable_update_rollback=$STABLE_UPDATE_ROLLBACK',
    'report_branch="reports/$HOST_SAFE/${START_TS}-stable100"': 'report_branch="reports/$HOST_SAFE/${START_TS}-stable-1.0.0"',
    'Record rc.1 acceptance on $HOST_SAFE': 'Record stable 1.0.0 acceptance on $HOST_SAFE',
    'STEP="upgrade-accepted-stable100-to-stable"': 'STEP="upgrade-accepted-rc1-to-stable"',
    'rc.1 did not become ready': 'stable 1.0.0 did not become ready',
    'installed rc.1 identity mismatch': 'installed stable 1.0.0 identity mismatch',
    'Intentional reboot for rc.1 boot acceptance; resume unit is armed': 'Intentional reboot for stable 1.0.0 boot acceptance; resume unit is armed',
    'current rc.1 backend is not ready': 'current stable 1.0.0 backend is not ready',
    'Resume preflight from already installed exact rc.1': 'Resume preflight from already installed exact stable 1.0.0',
    'current version is not rc.1': 'current version is not stable 1.0.0',
    'current rc.1 commit mismatch': 'current stable 1.0.0 commit mismatch',
    'accepted beta.1 previous release is unavailable': 'accepted rc.1 previous release is unavailable',
    'previous release is not accepted beta.1': 'previous release is not accepted rc.1',
    'previous beta.1 source identity mismatch': 'previous rc.1 source identity mismatch',
    '# Independently recorded in the immediately preceding beta.1/v4 evidence.': '# Independently recorded in the immediately preceding stable pre-reboot evidence.',
    'state hash differs from pre-upgrade beta.1 evidence': 'state hash differs from pre-upgrade rc.1 baseline evidence',
    'secrets hash differs from pre-upgrade beta.1 evidence': 'secrets hash differs from pre-upgrade rc.1 baseline evidence',
    'original trust marker missing after interrupted v5': 'original trust marker missing after interrupted stable acceptance',
    'ephemeral signing trust from v5 is incomplete': 'ephemeral signing trust from interrupted stable acceptance is incomplete',
    'installed trust is not the v5 ephemeral public key': 'installed trust is not the stable acceptance ephemeral public key',
    'v5 exact source checkout missing': 'stable exact source checkout missing',
    'v5 source checkout commit mismatch': 'stable source checkout commit mismatch',
    'rc update acceptance script is not executable': 'stable update acceptance script is not executable',
    'signed rc.1 package from v5 missing': 'signed stable 1.0.0 package is missing',
    'rc.1 identity changed across reboot': 'stable 1.0.0 identity changed across reboot',
    'STEP="restore-exact-stable100"': 'STEP="restore-exact-stable"',
    'Restore exact rc.1 after synthetic update tests': 'Restore exact stable 1.0.0 after synthetic update tests',
    'exact rc.1 restore not ready': 'exact stable 1.0.0 restore not ready',
    'exact rc.1 restore identity mismatch': 'exact stable 1.0.0 restore identity mismatch',
    'Repair and reinstall exact rc.1': 'Repair and reinstall exact stable 1.0.0',
    'rc.1 not ready after repair/reinstall': 'stable 1.0.0 not ready after repair/reinstall',
    'rc.1 not ready after preserve-state reinstall': 'stable 1.0.0 not ready after preserve-state reinstall',
    'logger -t control-center-stable100-acceptance "RC1 real-host acceptance PASSED commit=$RC_COMMIT report=${REPORT_BRANCH:-unknown}"': 'logger -t control-center-stable-100-acceptance "Stable 1.0.0 real-host acceptance PASSED commit=$RC_COMMIT report=${REPORT_BRANCH:-unknown}"',
    'an rc.1 acceptance run is already awaiting/resuming after reboot': 'a stable 1.0.0 acceptance run is already awaiting/resuming after reboot',
}
for old, new in replacements.items():
    count = src.count(old)
    if count != 1:
        raise SystemExit(f'ERROR: semantic anchor {old!r} expected once, found {count}')
    src = src.replace(old, new, 1)

# Guardrails against stale prerelease evidence language. Accepted rc.1 wording is intentionally allowed.
for forbidden in (
    'BETA_VERSION', 'BETA_COMMIT', 'BETA_PACKAGE', 'BETA_UPGRADE', 'RC_UPDATE_ROLLBACK',
    'beta_upgrade=', 'rc_update_rollback=', 'stable100', 'CONTROL CENTER RC1',
    'RC1 real-host acceptance', 'rc1-test-', 'accepted beta.1', 'previous beta.1',
    'v5 exact source', 'from v5', 'interrupted v5',
):
    if forbidden in src:
        raise SystemExit(f'ERROR: stale evidence semantic remains: {forbidden}')

Path(sys.argv[2]).write_text(src)
