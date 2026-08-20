#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

[[ $EUID -eq 0 ]] || { printf 'ERROR: rc.1 real-host acceptance v2 must run as root\n' >&2; exit 1; }

PARTS_COMMIT="7fae519c4458fe95f56b46fa60e9abb89a34f712"
EXPECTED_SHA256="5721480d2e8c7bb62c3f51344fb439ab83967e344a4bae6db4d1894c71c064c4"
BASE="https://raw.githubusercontent.com/ControlCenterSoft/srv-deployment/${PARTS_COMMIT}/ops/rc1-real-host-acceptance-v2"
WORK="$(mktemp -d /tmp/control-center-rc1-acceptance-v2-launch.XXXXXX)"
trap 'rm -rf -- "$WORK"' EXIT

for i in $(seq -w 0 15); do
  curl -fsSL "${BASE}/part${i}" -o "$WORK/part${i}"
done
cat "$WORK"/part{00..15} > "$WORK/acceptance.sh"
printf '%s  %s\n' "$EXPECTED_SHA256" "$WORK/acceptance.sh" | sha256sum -c -
chmod 0700 "$WORK/acceptance.sh"
exec bash "$WORK/acceptance.sh"
