#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

BOOTSTRAP_COMMIT='ae0c2dbf5786aebe933e1f779659dda3eafe5e59'
BOOTSTRAP_URL="https://raw.githubusercontent.com/ControlCenterSoft/srv-deployment/${BOOTSTRAP_COMMIT}/scripts/bootstrap-ops-agent.sh"
CURRENT_BIN='/usr/local/lib/control-center/current/control-center'
EXPECTED_VERSION='1.0.0'
EXPECTED_COMMIT='1b364ae88789696bf98537d21544de8a259d086d'
TMP="$(mktemp /tmp/control-center-ops-1.1.7.XXXXXX.sh)"
cleanup(){ rm -f -- "$TMP"; }
trap cleanup EXIT

before_version="$("$CURRENT_BIN" build-info --field version)"
before_commit="$("$CURRENT_BIN" build-info --field commit)"
[[ "$before_version" == "$EXPECTED_VERSION" && "$before_commit" == "$EXPECTED_COMMIT" ]]

curl -fsSLo "$TMP" "$BOOTSTRAP_URL"
chmod 0700 "$TMP"
bash -n "$TMP"
bash "$TMP"

after_version="$("$CURRENT_BIN" build-info --field version)"
after_commit="$("$CURRENT_BIN" build-info --field commit)"
[[ "$after_version" == "$EXPECTED_VERSION" && "$after_commit" == "$EXPECTED_COMMIT" ]]

printf 'OPS_AGENT_1_1_7_REMOTE_INSTALL=PASSED\n'
printf 'FROZEN_RUNTIME_UNCHANGED=true\n'
