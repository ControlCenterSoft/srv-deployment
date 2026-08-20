#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

BASE_COMMIT="44b358dc736998df42eca016324ea6de86e68fb4"
BASE_URL="https://raw.githubusercontent.com/ControlCenterSoft/srv-deployment/${BASE_COMMIT}/ops/stable-1.0.0-real-host-acceptance-v1/run-verified.sh"
BASE_BLOB_SHA1="7a3bcf32152fae84ecb499072628223775aefcc3"
FINAL_SCRIPT_SHA256="d2b8c4428d3a0a9716bd09f94ec92aac235df59da78abf13897a533bbab18b84"
WORK="$(mktemp -d /tmp/control-center-stable-final-launch.XXXXXX)"
trap 'rm -rf -- "$WORK"' EXIT

curl -fsSL "$BASE_URL" -o "$WORK/base.sh"
size="$(wc -c < "$WORK/base.sh" | tr -d ' ')"
actual_blob="$({ printf 'blob %s\0' "$size"; cat "$WORK/base.sh"; } | sha1sum | awk '{print $1}')"
[[ "$actual_blob" == "$BASE_BLOB_SHA1" ]] || {
  echo "ERROR: immutable stable base launcher blob mismatch: $actual_blob" >&2
  exit 1
}

python3 - "$WORK/base.sh" "$WORK/final-launcher.sh" "$FINAL_SCRIPT_SHA256" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]).read_text()
sha=sys.argv[3]
old='EXPECTED_STABLE_SCRIPT_SHA256=""'
new=f'EXPECTED_STABLE_SCRIPT_SHA256="{sha}"'
if src.count(old) != 1:
    raise SystemExit('ERROR: stable base SHA pin anchor mismatch')
Path(sys.argv[2]).write_text(src.replace(old,new,1))
PY
chmod 0700 "$WORK/final-launcher.sh"
bash -n "$WORK/final-launcher.sh"
grep -Fq "EXPECTED_STABLE_SCRIPT_SHA256=\"$FINAL_SCRIPT_SHA256\"" "$WORK/final-launcher.sh"

exec bash "$WORK/final-launcher.sh" "$@"
