#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
PARTS_COMMIT="30317ad75c2151db520ce1d3ca8459cb3e402326"
BASE="https://raw.githubusercontent.com/ControlCenterSoft/srv-deployment/${PARTS_COMMIT}/ops/beta1-resume-v5"
EXPECTED_SHA256="89b81fa85b10e2a2eea22dd288ff58fd30124ff130e8bb82a58a49d29f5ece96"
WORK="$(mktemp -d /tmp/control-center-beta1-v5-launch.XXXXXX)"
trap 'rm -rf -- "$WORK"' EXIT
for part in part00 part01 part02 part03; do
  curl -fsSL "${BASE}/${part}" -o "$WORK/$part"
done
cat "$WORK/part00" "$WORK/part01" "$WORK/part02" "$WORK/part03" > "$WORK/resume-v5.sh"
printf '%s  %s\n' "$EXPECTED_SHA256" "$WORK/resume-v5.sh" | sha256sum -c -
chmod 0700 "$WORK/resume-v5.sh"
exec bash "$WORK/resume-v5.sh"
