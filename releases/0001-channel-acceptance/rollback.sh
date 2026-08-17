#!/usr/bin/env bash
set -Eeuo pipefail

RELEASE_ID="0001-channel-acceptance"
MARKER="/var/lib/srv-deployment/release-markers/${RELEASE_ID}.applied"

rm -f "$MARKER"

printf 'ROLLBACK PASS: %s\n' "$RELEASE_ID"
