#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="maintenance-channel-resync"
STATE_ROOT="/var/lib/srv-deployment"
BACKUP_DIR="${STATE_ROOT}/backups/${REMOTE_SHA}-${RELEASE_ID}"
RELEASE_META="/var/lib/srv-control/release.json"

install -d -m 0750 "$BACKUP_DIR"
cp -a "$RELEASE_META" "$BACKUP_DIR/release.json"

sync_time="$(date -Is)"
tmp="$(mktemp /var/lib/srv-control/release.json.tmp.XXXXXX)"
python3 - "$RELEASE_META" "$tmp" "$REMOTE_SHA" "$sync_time" <<'PY'
import json
import pathlib
import sys

source = pathlib.Path(sys.argv[1])
target = pathlib.Path(sys.argv[2])
remote_sha = sys.argv[3]
sync_time = sys.argv[4]

payload = json.loads(source.read_text(encoding="utf-8"))
payload["git_sha"] = remote_sha
payload["synced_at"] = sync_time
target.write_text(
    json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY
chmod 0644 "$tmp"
mv -f "$tmp" "$RELEASE_META"

printf 'APPLY PASS: maintenance resync sha=%s synced_at=%s\n' "$REMOTE_SHA" "$sync_time"
