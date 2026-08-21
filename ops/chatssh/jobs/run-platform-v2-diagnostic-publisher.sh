#!/usr/bin/env bash
set -Eeuo pipefail
SRC='87563da615a16a1b6272893461501e0b62677055'
URL="https://raw.githubusercontent.com/ControlCenterSoft/srv-deployment/${SRC}/ops/chatssh/jobs/diagnose-platform-v2-prepare-publish.sh"
TMP="$(mktemp /tmp/platform-v2-diagnostic-publisher.XXXXXX.sh)"
trap 'rm -f -- "$TMP"' EXIT
curl -fsSLo "$TMP" "$URL"
chmod 0700 "$TMP"
bash -n "$TMP"
bash "$TMP"
