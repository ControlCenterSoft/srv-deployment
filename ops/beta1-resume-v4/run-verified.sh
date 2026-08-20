#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
PARTS_COMMIT="3199a2139ae47c5013d00bb9a59df30a46736089"
BASE="https://raw.githubusercontent.com/ControlCenterSoft/srv-deployment/${PARTS_COMMIT}/ops/beta1-resume-v4"
EXPECTED_SHA256="1bb1d9caf6fab807130a9acccbe48f1c2bf272a474161075e31ae4bfed71b017"
WORK="$(mktemp -d /tmp/control-center-beta1-v4-launch.XXXXXX)"
trap 'rm -rf -- "$WORK"' EXIT
for part in part00 part01 part02 part03; do
  curl -fsSL "${BASE}/${part}" -o "$WORK/$part"
done
cat "$WORK/part00" "$WORK/part01" "$WORK/part02" "$WORK/part03" > "$WORK/resume-v4.sh"
printf '%s  %s\n' "$EXPECTED_SHA256" "$WORK/resume-v4.sh" | sha256sum -c -
chmod 0700 "$WORK/resume-v4.sh"
exec bash "$WORK/resume-v4.sh"
