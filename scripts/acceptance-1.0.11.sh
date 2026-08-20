#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEGACY="$ROOT_DIR/scripts/acceptance-1.0.11-build5.sh"
TMP="$(mktemp /tmp/control-center-acceptance-1.0.11.XXXXXX)"
trap 'rm -f "$TMP"' EXIT
sed 's/20260819\.5/20260820.1/g' "$LEGACY" >"$TMP"
chmod 0755 "$TMP"
bash "$TMP" "$@"
