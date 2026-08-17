#!/usr/bin/env bash
set -Eeuo pipefail

RELEASE_ID="0001-channel-acceptance"
STATE_ROOT="/var/lib/srv-deployment"
MARKER_DIR="${STATE_ROOT}/release-markers"
MARKER="${MARKER_DIR}/${RELEASE_ID}.applied"

install -d -m 0750 "$MARKER_DIR"

tmp="$(mktemp "${MARKER}.tmp.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

{
    printf 'release_id=%s\n' "$RELEASE_ID"
    printf 'applied_at=%s\n' "$(date -Is)"
    printf 'hostname=%s\n' "$(hostname -f 2>/dev/null || hostname)"
} > "$tmp"

chmod 0640 "$tmp"
mv -f "$tmp" "$MARKER"
trap - EXIT

printf 'APPLY PASS: %s\n' "$RELEASE_ID"
