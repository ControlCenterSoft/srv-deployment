#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

[[ $EUID -eq 0 ]] || { echo 'ERROR: stable 1.0.0 safe final v2 acceptance must run as root' >&2; exit 1; }

SAFE_V1_COMMIT="2599c4b9522a864eaddde6debdcaca2816042140"
SAFE_V1_URL="https://raw.githubusercontent.com/ControlCenterSoft/srv-deployment/${SAFE_V1_COMMIT}/ops/stable-1.0.0-real-host-safe-final-v1/run-verified.sh"
SAFE_V1_BLOB_SHA1="2c3ad6c1822258ba136440c726b6ffd7646d6e69"
SAFE_V1_SCRIPT_SHA256="90c72a1f5c2b25894bdc5243c5d2f5b329c4093831b234188a2140928df28f9a"
PATCH_COMMIT="dc32337b0d26843443322d76d5dbe62e0fc7dd04"
PATCH_URL="https://raw.githubusercontent.com/ControlCenterSoft/srv-deployment/${PATCH_COMMIT}/ops/stable-1.0.0-real-host-safe-final-v2/semantic-patch.py"
PATCH_BLOB_SHA1="b5c98e8774ffca63165eb7e0c7f9fc0a5d18438c"
SAFE_V2_SCRIPT_SHA256="bc01510b1a7d2347329015974c1abd3f70ff9225e133ffed32827f68d30bd249"
WORK="$(mktemp -d /tmp/control-center-stable-safe-final-v2.XXXXXX)"
trap 'rm -rf -- "$WORK"' EXIT

verify_git_blob() {
  local path="$1" expected="$2" size actual
  size="$(wc -c < "$path" | tr -d ' ')"
  actual="$({ printf 'blob %s\0' "$size"; cat "$path"; } | sha1sum | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || {
    echo "ERROR: Git blob mismatch for $path: $actual" >&2
    exit 1
  }
}

curl -fsSL "$SAFE_V1_URL" -o "$WORK/safe-v1-wrapper.sh"
verify_git_blob "$WORK/safe-v1-wrapper.sh" "$SAFE_V1_BLOB_SHA1"
bash -n "$WORK/safe-v1-wrapper.sh"

STABLE_SAFE_BUILD_ONLY=1 OUTPUT_SAFE="$WORK/safe-v1.sh" bash "$WORK/safe-v1-wrapper.sh"
printf '%s  %s\n' "$SAFE_V1_SCRIPT_SHA256" "$WORK/safe-v1.sh" | sha256sum -c -
bash -n "$WORK/safe-v1.sh"

curl -fsSL "$PATCH_URL" -o "$WORK/semantic-patch.py"
verify_git_blob "$WORK/semantic-patch.py" "$PATCH_BLOB_SHA1"
python3 -m py_compile "$WORK/semantic-patch.py"
python3 "$WORK/semantic-patch.py" "$WORK/safe-v1.sh" "$WORK/safe-v2.sh"
printf '%s  %s\n' "$SAFE_V2_SCRIPT_SHA256" "$WORK/safe-v2.sh" | sha256sum -c -
bash -n "$WORK/safe-v2.sh"
chmod 0700 "$WORK/safe-v2.sh"

# Final stable artifact and accepted baseline identities.
grep -Fq 'RC_VERSION="1.0.0"' "$WORK/safe-v2.sh"
grep -Fq 'RC_COMMIT="1b364ae88789696bf98537d21544de8a259d086d"' "$WORK/safe-v2.sh"
grep -Fq 'RC_AMD64_SHA256="341f6a49646f92aca72692730ea61278cc03bfc1689d029d7a7ce573554fa735"' "$WORK/safe-v2.sh"
grep -Fq 'RC_ARM64_SHA256="5e6e959f39bd4cb554e902908863c92eb5c697f4d99b55ca97fa4735ec9419fe"' "$WORK/safe-v2.sh"
grep -Fq 'BASELINE_VERSION="1.0.0-rc.1"' "$WORK/safe-v2.sh"
grep -Fq 'BASELINE_COMMIT="77b62d5829a46b1b29698495043146d79f37dc48"' "$WORK/safe-v2.sh"

# Evidence semantics and recovery invariants.
grep -Fq 'CONTROL CENTER 1.0.0 STABLE REAL-HOST ACCEPTANCE' "$WORK/safe-v2.sh"
grep -Fq 'baseline_upgrade=$BASELINE_UPGRADE' "$WORK/safe-v2.sh"
grep -Fq 'stable_update_rollback=$STABLE_UPDATE_ROLLBACK' "$WORK/safe-v2.sh"
grep -Fq 'report_branch="reports/$HOST_SAFE/${START_TS}-stable-1.0.0"' "$WORK/safe-v2.sh"
grep -Fq 'STEP="upgrade-accepted-rc1-to-stable"' "$WORK/safe-v2.sh"
grep -Fq 'STEP="restore-exact-stable"' "$WORK/safe-v2.sh"
python3 - "$WORK/safe-v2.sh" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]).read_text()
start=src.index('recover_exact_rc() {\n')
next_fn=src.index('on_error() {',start)
end=src.rfind('}',start,next_fn)+1
block=src[start:end]
for item in (
    '$BASELINE_PACKAGE', '--allow-downgrade', 'recovery-accepted-rc1',
    'verify-release', 'CONTROL_CENTER_BINARY="$recovery_dir/control-center"',
    'systemctl reset-failed control-center.service',
):
    assert item in block, item
assert '$RC_PACKAGE' not in block
for forbidden in (
    'BETA_VERSION','BETA_COMMIT','BETA_PACKAGE','BETA_UPGRADE','RC_UPDATE_ROLLBACK',
    'beta_upgrade=','rc_update_rollback=','stable100','CONTROL CENTER RC1',
    'RC1 real-host acceptance','rc1-test-','accepted beta.1','previous beta.1',
    'v5 exact source','from v5','interrupted v5',
):
    assert forbidden not in src, forbidden
print('SAFE_V2_RECOVERY_AND_EVIDENCE=PASSED')
PY

if [[ ${STABLE_SAFE_V2_BUILD_ONLY:-0} == 1 ]]; then
  cp "$WORK/safe-v2.sh" "${OUTPUT_SAFE_V2:?OUTPUT_SAFE_V2 required in build-only mode}"
  echo 'STABLE_SAFE_V2_BUILD_ONLY=PASSED'
  exit 0
fi

exec bash "$WORK/safe-v2.sh" "$@"
