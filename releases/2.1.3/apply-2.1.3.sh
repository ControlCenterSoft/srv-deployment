#!/usr/bin/env bash
set -Eeuo pipefail
umask 027
PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SYSTEM="$RELEASE_DIR/system"
STATE=/var/lib/srv-control
BACKUP="/var/lib/srv-deployment/backups/${REMOTE_SHA}-2.1.3"
mkdir -p "$BACKUP"
cp -a /etc/nginx/sites-available/srv-control "$BACKUP/nginx-site" 2>/dev/null || true
cp -a /etc/chrony "$BACKUP/chrony" 2>/dev/null || true
cp -a "$STATE/release.json" "$BACKUP/release.json"
install -d -m 0755 /usr/local/libexec
install -m 0755 "$SYSTEM/control-center-web-tls" /usr/local/libexec/control-center-web-tls
install -m 0755 "$SYSTEM/control-center-chrony" /usr/local/libexec/control-center-chrony
/usr/local/libexec/control-center-web-tls ensure
/usr/local/libexec/control-center-chrony ensure-ad-profile || true
python3 - "$STATE/release.json" "$REMOTE_SHA" <<'PY'
import json,sys,datetime,pathlib
p=pathlib.Path(sys.argv[1])
p.write_text(json.dumps({"version":"2.1.3","release_id":"2.1.3","synced_at":datetime.datetime.now().astimezone().isoformat(),"git_sha":sys.argv[2]},indent=2)+"\n")
PY
systemctl restart srv-control.service
echo "APPLY 2.1.3 PASS: HTTPS canonicalized; Chrony management helpers installed"
