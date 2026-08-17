#!/usr/bin/env bash
set -Eeuo pipefail
PROJECT="${1:-/opt/srv-control}"
fail(){ echo "ACCEPTANCE FAIL: $*" >&2; exit 1; }
health="$(curl -fsS --max-time 10 http://127.0.0.1:8876/api/v1/health)" || fail "health endpoint unavailable"
python3 - "$health" <<'PY' || exit 1
import json,sys
p=json.loads(sys.argv[1]); assert p.get('ok') is True,p; assert (p.get('data') or {}).get('release',{}).get('version')=='1.4.0',p
PY
runuser -u srv-control -- env PYTHONPATH="$PROJECT" PYTHONDONTWRITEBYTECODE=1 "$PROJECT/venv/bin/python" - <<'PY' || fail "release14 imports failed"
import app.main
from app.core import release14
from app.routers import release14 as router
print('import-ok')
PY
REV="$(runuser -u srv-control -- env PYTHONPATH="$PROJECT" PYTHONDONTWRITEBYTECODE=1 "$PROJECT/venv/bin/alembic" -c "$PROJECT/alembic.ini" current)"
grep -q '14f0a1400001' <<<"$REV" || fail "migration head missing: $REV"
for table in dhcp_configs dhcp_options dhcp_reservations pxe_configuration_profiles pxe_profile_configuration_profiles folder_redirect_profiles folder_redirect_assignments; do
  runuser -u srv-control -- psql -d srv_control -Atqc "SELECT to_regclass('public.$table') IS NOT NULL" | grep -qx t || fail "table missing: $table"
done
systemctl is-enabled --quiet srv-control-release14-agent.path || fail "release14 action path disabled"
systemctl is-active --quiet srv-control-release14-agent.path || fail "release14 action path inactive"
systemctl is-enabled --quiet srv-control-backup-retention.path || fail "backup retention path disabled"
boot="$(curl -fsS --max-time 10 'http://127.0.0.1:8876/pxe/boot.ipxe?mac=02:00:00:00:00:01')" || fail "public PXE authorization endpoint unavailable"
grep -q 'not authorized' <<<"$boot" || fail "unknown PXE device was not denied"
! grep -qiE 'kernel|initrd.*boot.wim|autoinstall' <<<"$boot" || fail "unknown PXE device received installation payload"
echo "ACCEPTANCE PASS: release=1.4.0 migration=14f0a1400001 deny-by-default=ok"
