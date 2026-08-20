#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

V1_COMMIT="8d322ce33997a95e07276a1f778208cffc9be4dd"
V1_URL="https://raw.githubusercontent.com/ControlCenterSoft/srv-deployment/${V1_COMMIT}/ops/stable-1.0.0-real-host-acceptance-v1/run-verified.sh"
V1_BLOB_SHA1="621b2fa1d7e495eff2a6887459d9886c74c02200"
EXPECTED_FINAL_SCRIPT_SHA256=""
BUILD_ONLY="${STABLE_ACCEPTANCE_BUILD_ONLY:-0}"
WORK="$(mktemp -d /tmp/control-center-stable-v2-launch.XXXXXX)"
trap 'rm -rf -- "$WORK"' EXIT

curl -fsSL "$V1_URL" -o "$WORK/v1.sh"
size="$(wc -c < "$WORK/v1.sh" | tr -d ' ')"
actual_blob="$({ printf 'blob %s\0' "$size"; cat "$WORK/v1.sh"; } | sha1sum | awk '{print $1}')"
[[ "$actual_blob" == "$V1_BLOB_SHA1" ]] || {
  echo "ERROR: immutable stable v1 launcher blob mismatch: $actual_blob" >&2
  exit 1
}

python3 - "$WORK/v1.sh" "$WORK/v2-builder.sh" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]).read_text()
old="""# Stable synthetic lifecycle is 1.0.1 -> broken 1.0.2 -> rollback.\ncount = src.count('scripts/rc1-update-acceptance.sh')\nif count != 1:\n    raise SystemExit(f'ERROR: rc update acceptance path count={count}')\nsrc = src.replace('scripts/rc1-update-acceptance.sh', 'scripts/stable-update-acceptance.sh')\n"""
new="""# Stable synthetic lifecycle is 1.0.1 -> broken 1.0.2 -> rollback.\none('\\\"$SOURCE_DIR\\\"/scripts/build.sh \\\"$SOURCE_DIR\\\"/scripts/build-release.sh \\\"$SOURCE_DIR\\\"/scripts/rc1-update-acceptance.sh', '\\\"$SOURCE_DIR\\\"/scripts/build.sh \\\"$SOURCE_DIR\\\"/scripts/build-release.sh \\\"$SOURCE_DIR\\\"/scripts/stable-update-acceptance.sh', 'stable syntax acceptance path')\none('[[ -x \\\"$SOURCE_DIR/scripts/rc1-update-acceptance.sh\\\" ]] || die \\\"rc update acceptance script is not executable\\\"', '[[ -x \\\"$SOURCE_DIR/scripts/stable-update-acceptance.sh\\\" ]] || die \\\"stable update acceptance script is not executable\\\"', 'stable executable acceptance path')\none('\\\"$SOURCE_DIR/scripts/rc1-update-acceptance.sh\\\"', '\\\"$SOURCE_DIR/scripts/stable-update-acceptance.sh\\\"', 'stable execution acceptance path')\n"""
if src.count(old) != 1:
    raise SystemExit('ERROR: stable v1 patch block mismatch')
Path(sys.argv[2]).write_text(src.replace(old,new,1))
PY
chmod 0700 "$WORK/v2-builder.sh"

if [[ $EUID -eq 0 ]]; then
  STABLE_ACCEPTANCE_BUILD_ONLY=1 OUTPUT_STABLE="$WORK/final.sh" bash "$WORK/v2-builder.sh"
else
  sudo env STABLE_ACCEPTANCE_BUILD_ONLY=1 OUTPUT_STABLE="$WORK/final.sh" bash "$WORK/v2-builder.sh"
fi

if [[ ! -r "$WORK/final.sh" ]]; then
  sudo chmod 0644 "$WORK/final.sh"
fi
bash -n "$WORK/final.sh"
actual_sha="$(sha256sum "$WORK/final.sh" | awk '{print $1}')"
printf 'STABLE_FINAL_SCRIPT_SHA256=%s\n' "$actual_sha"

grep -F 'RC_VERSION="1.0.0"' "$WORK/final.sh" >/dev/null
grep -F 'RC_COMMIT="1b364ae88789696bf98537d21544de8a259d086d"' "$WORK/final.sh" >/dev/null
grep -F 'BETA_VERSION="1.0.0-rc.1"' "$WORK/final.sh" >/dev/null
grep -F 'BETA_COMMIT="77b62d5829a46b1b29698495043146d79f37dc48"' "$WORK/final.sh" >/dev/null
[[ "$(grep -c 'scripts/stable-update-acceptance.sh' "$WORK/final.sh")" -eq 3 ]]
! grep -Fq 'scripts/rc1-update-acceptance.sh' "$WORK/final.sh"

if [[ "$BUILD_ONLY" == 1 ]]; then
  cp "$WORK/final.sh" "${OUTPUT_STABLE:?OUTPUT_STABLE required in build-only mode}"
  echo 'STABLE_V2_BUILD_ONLY=PASSED'
  exit 0
fi

[[ $EUID -eq 0 ]] || { echo 'ERROR: stable acceptance execution requires root' >&2; exit 1; }
[[ -n "$EXPECTED_FINAL_SCRIPT_SHA256" ]] || { echo 'ERROR: final stable orchestrator SHA is not pinned' >&2; exit 1; }
[[ "$actual_sha" == "$EXPECTED_FINAL_SCRIPT_SHA256" ]] || { echo "ERROR: final stable orchestrator SHA mismatch: $actual_sha" >&2; exit 1; }

exec bash "$WORK/final.sh"
