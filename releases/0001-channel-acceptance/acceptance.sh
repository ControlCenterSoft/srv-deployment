#!/usr/bin/env bash
set -Eeuo pipefail

RELEASE_ID="0001-channel-acceptance"
MARKER="/var/lib/srv-deployment/release-markers/${RELEASE_ID}.applied"

fail() {
    printf 'ACCEPTANCE FAIL: %s\n' "$*" >&2
    exit 1
}

[[ -s "$MARKER" ]] || fail "apply marker is missing"
grep -Fxq "release_id=${RELEASE_ID}" "$MARKER" || fail "release marker has unexpected id"
systemctl is-active --quiet srv-control.service || fail "srv-control.service is not active"

printf 'ACCEPTANCE PASS: %s\n' "$RELEASE_ID"
