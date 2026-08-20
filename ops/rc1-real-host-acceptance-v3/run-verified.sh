#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

[[ $EUID -eq 0 ]] || { printf 'ERROR: rc.1 real-host acceptance v3 must run as root\n' >&2; exit 1; }

PARTS_COMMIT="5ea0c1ac68f4af19ece6ec7b3c15b7c2f3c10af6"
EXPECTED_SHA256="00118701cb2a7dd0c11ae357c9e55f1ff8141bf6b4f978175c03e58e2a21a34e"
BASE="https://raw.githubusercontent.com/ControlCenterSoft/srv-deployment/${PARTS_COMMIT}/ops/rc1-real-host-acceptance-v3"
WORK="$(mktemp -d /tmp/control-center-rc1-acceptance-v3-launch.XXXXXX)"
trap 'rm -rf -- "$WORK"' EXIT

for i in $(seq -w 0 15); do
  curl -fsSL "${BASE}/part${i}" -o "$WORK/part${i}"
done
cat "$WORK"/part{00..15} > "$WORK/acceptance.sh"
printf '%s  %s\n' "$EXPECTED_SHA256" "$WORK/acceptance.sh" | sha256sum -c -
chmod 0700 "$WORK/acceptance.sh"
exec bash "$WORK/acceptance.sh"
