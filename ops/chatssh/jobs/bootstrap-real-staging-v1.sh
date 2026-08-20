#!/usr/bin/env bash
set -Eeuo pipefail
url='https://raw.githubusercontent.com/ControlCenterSoft/srv-deployment/461d3fd7a6159fc6034439fd253a3f048f3e48a9/scripts/bootstrap-real-staging.sh'
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
curl -fsSL --max-time 30 "$url" -o "$tmp"
bash "$tmp"
