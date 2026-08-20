#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
SCRIPT_COMMIT="8ef343a67ec06c59b0f11f3a439ecea27c3e2e88"
SCRIPT_URL="https://raw.githubusercontent.com/ControlCenterSoft/srv-deployment/${SCRIPT_COMMIT}/ops/beta1-acceptance/run-v3.sh"
EXPECTED_SHA256="73231743496c4a7b9387b80ce12ce3360800a91eb04951ed0ca6fe05a8cf49b9"
WORK="$(mktemp -d /tmp/control-center-beta1-v3-launch.XXXXXX)"
trap 'rm -rf -- "$WORK"' EXIT
curl -fsSL "$SCRIPT_URL" -o "$WORK/run-v3.sh"
printf '%s  %s\n' "$EXPECTED_SHA256" "$WORK/run-v3.sh" | sha256sum -c -
chmod 0700 "$WORK/run-v3.sh"
exec bash "$WORK/run-v3.sh"
