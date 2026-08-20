#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

[[ $EUID -eq 0 ]] || { echo 'ERROR: stable 1.0.0 safe final acceptance must run as root' >&2; exit 1; }

BASE_COMMIT="4efcf72a363b9c0d55697af0afb159ec3dd794c1"
BASE_URL="https://raw.githubusercontent.com/ControlCenterSoft/srv-deployment/${BASE_COMMIT}/ops/stable-1.0.0-real-host-safe-final/base-launcher.sh"
BASE_BLOB_SHA1="4f03a6eb1b7ff5ad3fcce88e8d8005755e9b39da"
SAFE_SCRIPT_SHA256="90c72a1f5c2b25894bdc5243c5d2f5b329c4093831b234188a2140928df28f9a"
WORK="$(mktemp -d /tmp/control-center-stable-safe-final-v1.XXXXXX)"
trap 'rm -rf -- "$WORK"' EXIT

curl -fsSL "$BASE_URL" -o "$WORK/base-launcher.sh"
size="$(wc -c < "$WORK/base-launcher.sh" | tr -d ' ')"
actual_blob="$({ printf 'blob %s\0' "$size"; cat "$WORK/base-launcher.sh"; } | sha1sum | awk '{print $1}')"
[[ "$actual_blob" == "$BASE_BLOB_SHA1" ]] || {
  echo "ERROR: immutable safe base launcher Git blob mismatch: $actual_blob" >&2
  exit 1
}
bash -n "$WORK/base-launcher.sh"

python3 - "$WORK/base-launcher.sh" "$WORK/final-launcher.sh" "$SAFE_SCRIPT_SHA256" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]).read_text()
sha=sys.argv[3]
old='EXPECTED_SAFE_SCRIPT_SHA256=""'
new=f'EXPECTED_SAFE_SCRIPT_SHA256="{sha}"'
if src.count(old) != 1:
    raise SystemExit('ERROR: safe base SHA pin anchor mismatch')
Path(sys.argv[2]).write_text(src.replace(old,new,1))
PY
chmod 0700 "$WORK/final-launcher.sh"
bash -n "$WORK/final-launcher.sh"
grep -Fq "EXPECTED_SAFE_SCRIPT_SHA256=\"$SAFE_SCRIPT_SHA256\"" "$WORK/final-launcher.sh"

exec bash "$WORK/final-launcher.sh" "$@"
