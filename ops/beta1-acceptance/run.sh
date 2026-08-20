#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

PARTS_COMMIT="8b5b440f1ba58969910a78911eeed0ebafd67c80"
BASE="https://raw.githubusercontent.com/ControlCenterSoft/srv-deployment/${PARTS_COMMIT}/ops/beta1-acceptance"
EXPECTED_SHA256="ada392095951c9cda7acd920f0974a2bfcde4053553e9a0c3ef973450458a0e2"
WORK="$(mktemp -d /tmp/control-center-beta1-launch.XXXXXX)"
trap 'rm -rf -- "$WORK"' EXIT

for part in part00 part01 part02 part03; do
  curl -fsSL "${BASE}/${part}" -o "$WORK/$part"
done
cat "$WORK/part00" "$WORK/part01" "$WORK/part02" "$WORK/part03" > "$WORK/acceptance.sh"
printf '%s  %s\n' "$EXPECTED_SHA256" "$WORK/acceptance.sh" | sha256sum -c -
chmod 0700 "$WORK/acceptance.sh"
exec bash "$WORK/acceptance.sh"
