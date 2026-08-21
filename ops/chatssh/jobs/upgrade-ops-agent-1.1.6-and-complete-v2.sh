#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'CHATSSH_UPGRADE_FAILED: root required' >&2; exit 1; }

BOOTSTRAP_COMMIT='3940b146b395ce514523894fb6f90a38f8e5c928'
BOOTSTRAP_URL="https://raw.githubusercontent.com/ControlCenterSoft/srv-deployment/${BOOTSTRAP_COMMIT}/scripts/bootstrap-platform-v2-staging-complete.sh"
TMP="$(mktemp /tmp/control-center-staging-complete.XXXXXX.sh)"
cleanup(){ rm -f -- "$TMP"; }
trap cleanup EXIT

curl -fsSLo "$TMP" "$BOOTSTRAP_URL"
chmod 0700 "$TMP"
bash -n "$TMP"
bash "$TMP"

printf 'CHATSSH_ONE_TIME_MIGRATION=PASSED\n'
printf 'BOOTSTRAP_COMMIT=%s\n' "$BOOTSTRAP_COMMIT"
