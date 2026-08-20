#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

[[ $EUID -eq 0 ]] || { printf 'ERROR: rc.1 real-host acceptance must run as root\n' >&2; exit 1; }

PARTS_COMMIT="cce9f3b163d6a56ddd22a1afe3c715eb3f3c1181"
EXPECTED_SHA256="32288bc7634d245372e260d0f24573afaffa8dbf8090cbe60b794e9eff60876a"
BASE="https://raw.githubusercontent.com/ControlCenterSoft/srv-deployment/${PARTS_COMMIT}/ops/rc1-real-host-acceptance-v1"
WORK="$(mktemp -d /tmp/control-center-rc1-acceptance-launch.XXXXXX)"
trap 'rm -rf -- "$WORK"' EXIT

for part in part00 part01 part02 part03; do
  curl -fsSL "${BASE}/${part}" -o "$WORK/$part"
done
cat "$WORK/part00" "$WORK/part01" "$WORK/part02" "$WORK/part03" > "$WORK/acceptance.sh"
printf '%s  %s\n' "$EXPECTED_SHA256" "$WORK/acceptance.sh" | sha256sum -c -
chmod 0700 "$WORK/acceptance.sh"
exec bash "$WORK/acceptance.sh"
