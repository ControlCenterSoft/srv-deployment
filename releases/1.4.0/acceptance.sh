#!/usr/bin/env bash
set -Eeuo pipefail
PROJECT="${1:-/opt/srv-control}"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
fail(){ echo "ACCEPTANCE FAIL: $*" >&2; exit 1; }

health="$(curl -fsS --max-time 10 http://127.0.0.1:8876/api/v1/health)" || fail "health endpoint unavailable"
python3 - "$health" <<'PY' || exit 1
import json,sys
p=json.loads(sys.argv[1]); assert p.get('ok') is True,p; assert (p.get('data') or {}).get('release',{}).get('version')=='1.4.0',p
PY

python3 "$RELEASE_DIR/tests/pxe_contract.py" || fail "PXE firmware/safety contract failed"
python3 -m py_compile /usr/local/libexec/srv-control-release14-agent || fail "installed release14 root agent syntax invalid"
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

# Deny-by-default must hold for every firmware class without exposing a boot payload.
for query in \
  'mac=02:00:00:00:00:01&platform=pcbios&buildarch=i386' \
  'mac=02:00:00:00:00:02&platform=efi&buildarch=i386' \
  'mac=02:00:00:00:00:03&platform=efi&buildarch=x86_64' \
  'mac=02:00:00:00:00:04&platform=efi&buildarch=arm32' \
  'mac=02:00:00:00:00:05&platform=efi&buildarch=arm64'; do
  boot="$(curl -fsS --max-time 10 "http://127.0.0.1:8876/pxe/boot.ipxe?$query")" || fail "public PXE authorization endpoint unavailable for $query"
  grep -q 'not authorized' <<<"$boot" || fail "unknown PXE device was not denied: $query"
  ! grep -qiE '(^|[[:space:]])(kernel|initrd|shim|imgfetch).*|autoinstall|preseed/url|/pxe/consume/' <<<"$boot" || fail "unknown PXE device received installation payload: $query"
done

# Private profile files must never be reachable through the public static media mount.
sentinel="/srv/pxe/profiles/.srvcc-acceptance-private-$$"
install -d -m 0750 -o root -g srv-control /srv/pxe/profiles
printf 'private\n' > "$sentinel"
chmod 0640 "$sentinel"
cleanup(){ rm -f -- "$sentinel"; }
trap cleanup EXIT
code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "http://127.0.0.1:8876/pxe/files/profiles/$(basename "$sentinel")")" || true
[[ "$code" == 404 ]] || fail "private PXE profile leaked through static media root: HTTP $code"
code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 'http://127.0.0.1:8876/pxe/profile/999999/not-a-token/boot.ipxe')" || true
[[ "$code" == 404 ]] || fail "invalid PXE profile token did not return 404: HTTP $code"

# Only a runtime installed/repaired by 1.4 owns the HTTP entry marker. A legacy
# PXE installation is preserved during the Control Center upgrade and can be
# explicitly upgraded from Services; it must not roll back the whole 1.4 release.
if [[ -f /srv/pxe/media/boot/entry.ipxe ]]; then
  /usr/local/libexec/srv-control-release14-agent --validate-pxe >/tmp/srvcc-pxe-validation.txt || fail "managed live PXE runtime validation failed"
  grep -q 'PXE runtime validation passed' /tmp/srvcc-pxe-validation.txt || fail "live PXE validation did not report success"
  rm -f /tmp/srvcc-pxe-validation.txt
elif systemctl is-active --quiet tftpd-hpa.service; then
  echo "ACCEPTANCE INFO: legacy/unmanaged PXE runtime detected; Control Center upgrade preserved it and PXE repair is required before 1.4 runtime guarantees apply"
fi

echo "ACCEPTANCE PASS: release=1.4.0 migration=14f0a1400001 deny-by-default=ok firmware-contract=ok private-profiles=ok"
