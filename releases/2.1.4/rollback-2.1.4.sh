#!/usr/bin/env bash
set -Eeuo pipefail
umask 027
PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$RELEASE_DIR/../.." && pwd -P)"
BASE="$REPO_ROOT/releases/2.1.2"
STATE=/var/lib/srv-control
META="$STATE/release.json"
BACKUP="/var/lib/srv-deployment/backups/${REMOTE_SHA}-2.1.4"
fail(){ echo "ROLLBACK 2.1.4 FAIL: $*" >&2; exit 1; }
[[ -s "$BACKUP/state/original-source-version" ]] || fail "original source marker missing"
ORIGINAL_SOURCE="$(cat "$BACKUP/state/original-source-version")"
if [[ -s "$BACKUP/state/release.json.before" ]]; then
  cp -a "$BACKUP/state/release.json.before" "$META"
fi
if [[ "$ORIGINAL_SOURCE" != "2.1.2" ]]; then
  bash "$BASE/rollback-2.1.2.sh" "$PROJECT" "$REMOTE_SHA"
fi
curl -fsS --max-time 10 http://127.0.0.1:8876/api/v1/health >/dev/null 2>&1 || true
echo "ROLLBACK 2.1.4 PASS: runtime returned to source=$ORIGINAL_SOURCE; repository-only clean-installer change requires no installed-file rollback"
