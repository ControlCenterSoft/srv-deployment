#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

[[ $EUID -eq 0 ]] || { echo 'ERROR: stable safe acceptance launcher must run as root' >&2; exit 1; }

BUILD_ONLY="${STABLE_SAFE_BUILD_ONLY:-0}"
VERIFIED_WRAPPER_COMMIT="91fdb0a4ed5a8d781787926f575269c6bd6beabb"
VERIFIED_WRAPPER_URL="https://raw.githubusercontent.com/ControlCenterSoft/srv-deployment/${VERIFIED_WRAPPER_COMMIT}/ops/stable-1.0.0-real-host-acceptance-final/run-verified.sh"
VERIFIED_WRAPPER_BLOB_SHA1="7665827ace6b0e9ab8d7dd920ba75e55024ecd22"
VERIFIED_BASE_SCRIPT_SHA256="d2b8c4428d3a0a9716bd09f94ec92aac235df59da78abf13897a533bbab18b84"
EXPECTED_SAFE_SCRIPT_SHA256=""
WORK="$(mktemp -d /tmp/control-center-stable-safe-launch.XXXXXX)"
trap 'rm -rf -- "$WORK"' EXIT

curl -fsSL "$VERIFIED_WRAPPER_URL" -o "$WORK/verified-wrapper.sh"
size="$(wc -c < "$WORK/verified-wrapper.sh" | tr -d ' ')"
actual_blob="$({ printf 'blob %s\0' "$size"; cat "$WORK/verified-wrapper.sh"; } | sha1sum | awk '{print $1}')"
[[ "$actual_blob" == "$VERIFIED_WRAPPER_BLOB_SHA1" ]] || {
  echo "ERROR: verified stable wrapper Git blob mismatch: $actual_blob" >&2
  exit 1
}
bash -n "$WORK/verified-wrapper.sh"

STABLE_ACCEPTANCE_BUILD_ONLY=1 OUTPUT_STABLE="$WORK/base-stable.sh" bash "$WORK/verified-wrapper.sh"
printf '%s  %s\n' "$VERIFIED_BASE_SCRIPT_SHA256" "$WORK/base-stable.sh" | sha256sum -c -
bash -n "$WORK/base-stable.sh"

python3 - "$WORK/base-stable.sh" "$WORK/safe-stable.sh" <<'PY'
from pathlib import Path
import sys

src = Path(sys.argv[1]).read_text()
start_marker = 'recover_exact_rc() {\n'
if src.count(start_marker) != 1:
    raise SystemExit('ERROR: recovery function start is not unique')
start = src.index(start_marker)
next_fn = src.index('on_error() {', start)
end = src.rfind('}', start, next_fn) + 1
if end <= start:
    raise SystemExit('ERROR: recovery function end not found')
old = src[start:end]
for required in ('$RC_PACKAGE', 'control-center-update', 'install/install.sh'):
    if required not in old:
        raise SystemExit(f'ERROR: inherited recovery contract missing {required}')
if '$BETA_PACKAGE' in old:
    raise SystemExit('ERROR: inherited recovery unexpectedly already uses accepted baseline')

new = r'''recover_exact_rc() {
  set +e
  if [[ -f "$PUBLIC_KEY" ]]; then install_test_trust >/dev/null 2>&1 || true; fi
  if [[ -f "$BETA_PACKAGE" && -x /usr/local/sbin/control-center-update ]]; then
    CONTROL_CENTER_UPDATE_HEALTH_URL="$BACKEND_URL" /usr/local/sbin/control-center-update --package "$BETA_PACKAGE" --allow-downgrade >/dev/null 2>&1 || true
  elif [[ -f "$BETA_PACKAGE" && -x "$SOURCE_DIR/install/install.sh" && -x "$SOURCE_DIR/dist/control-center-linux-$GOARCH" ]]; then
    local recovery_dir="$BASE/recovery-accepted-rc1"
    rm -rf -- "$recovery_dir"
    mkdir -p "$recovery_dir"
    tar -xzf "$BETA_PACKAGE" -C "$recovery_dir" >/dev/null 2>&1 || true
    if [[ -x "$recovery_dir/control-center" && -f "$recovery_dir/manifest.json" && -f "$recovery_dir/manifest.sig" ]]; then
      if "$SOURCE_DIR/dist/control-center-linux-$GOARCH" verify-release \
        --manifest "$recovery_dir/manifest.json" --signature "$recovery_dir/manifest.sig" \
        --public-key "$PUBLIC_KEY" --artifact "$recovery_dir/control-center" --field release-id >/dev/null 2>&1; then
        CONTROL_CENTER_BINARY="$recovery_dir/control-center" CONTROL_CENTER_UPDATE_PUBLIC_KEY="$PUBLIC_KEY" CONTROL_CENTER_ACCEPTANCE_URL="$BACKEND_URL" \
          "$SOURCE_DIR/install/install.sh" --reinstall >/dev/null 2>&1 || true
      fi
    fi
  fi
  systemctl reset-failed control-center.service >/dev/null 2>&1 || true
  systemctl start control-center.service >/dev/null 2>&1 || true
  set -e
}'''
src = src[:start] + new + src[end:]
Path(sys.argv[2]).write_text(src)
PY

bash -n "$WORK/safe-stable.sh"

# Immutable release identity and accepted baseline invariants.
grep -Fq 'RC_VERSION="1.0.0"' "$WORK/safe-stable.sh"
grep -Fq 'RC_COMMIT="1b364ae88789696bf98537d21544de8a259d086d"' "$WORK/safe-stable.sh"
grep -Fq 'RC_AMD64_SHA256="341f6a49646f92aca72692730ea61278cc03bfc1689d029d7a7ce573554fa735"' "$WORK/safe-stable.sh"
grep -Fq 'RC_ARM64_SHA256="5e6e959f39bd4cb554e902908863c92eb5c697f4d99b55ca97fa4735ec9419fe"' "$WORK/safe-stable.sh"
grep -Fq 'BETA_VERSION="1.0.0-rc.1"' "$WORK/safe-stable.sh"
grep -Fq 'BETA_COMMIT="77b62d5829a46b1b29698495043146d79f37dc48"' "$WORK/safe-stable.sh"
grep -Fq 'BASE="/opt/control-center-stable-acceptance"' "$WORK/safe-stable.sh"
grep -Fq 'scripts/stable-update-acceptance.sh' "$WORK/safe-stable.sh"
! grep -Fq 'scripts/rc1-update-acceptance.sh' "$WORK/safe-stable.sh"

# Failure recovery must target accepted rc.1, including the updater-missing lifecycle window.
python3 - "$WORK/safe-stable.sh" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]).read_text()
start=src.index('recover_exact_rc() {\n')
next_fn=src.index('on_error() {',start)
end=src.rfind('}',start,next_fn)+1
if end <= start:
    raise SystemExit('ERROR: safe recovery function end not found')
block=src[start:end]
required=(
  '$BETA_PACKAGE', '--allow-downgrade', 'recovery-accepted-rc1',
  'verify-release', 'CONTROL_CENTER_BINARY="$recovery_dir/control-center"',
  'systemctl reset-failed control-center.service',
)
for item in required:
    if item not in block:
        raise SystemExit(f'ERROR: safe recovery missing {item}')
if '$RC_PACKAGE' in block:
    raise SystemExit('ERROR: safe recovery can restore unaccepted stable candidate')
print('SAFE_RECOVERY_AUDIT=PASSED')
PY

# Error and success cleanup must preserve the original trust boundary and remove ephemeral keys.
grep -Fq 'restore_original_trust' "$WORK/safe-stable.sh"
grep -Fq 'rm -f "$PRIVATE_KEY" "$PUBLIC_KEY"' "$WORK/safe-stable.sh"
grep -Fq 'FINAL_STATUS="PASSED"' "$WORK/safe-stable.sh"
grep -Fq '=== STABLE 1.0.0 REAL-HOST ACCEPTANCE PASSED ===' "$WORK/safe-stable.sh"

actual_safe_sha="$(sha256sum "$WORK/safe-stable.sh" | awk '{print $1}')"
printf 'SAFE_STABLE_SCRIPT_SHA256=%s\n' "$actual_safe_sha"

if [[ "$BUILD_ONLY" == 1 ]]; then
  cp "$WORK/safe-stable.sh" "${OUTPUT_SAFE:?OUTPUT_SAFE required in build-only mode}"
  printf 'STABLE_SAFE_BUILD_ONLY=PASSED\n'
  exit 0
fi

[[ -n "$EXPECTED_SAFE_SCRIPT_SHA256" ]] || {
  echo 'ERROR: production execution disabled until safe stable orchestrator SHA is pinned' >&2
  exit 1
}
[[ "$actual_safe_sha" == "$EXPECTED_SAFE_SCRIPT_SHA256" ]] || {
  echo "ERROR: safe stable orchestrator SHA mismatch: $actual_safe_sha" >&2
  exit 1
}

exec bash "$WORK/safe-stable.sh"
