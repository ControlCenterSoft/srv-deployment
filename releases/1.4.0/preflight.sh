#!/usr/bin/env bash
set -Eeuo pipefail
PROJECT="${1:-/opt/srv-control}"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
fail(){ echo "PREFLIGHT FAIL: $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || fail "must run as root"
[[ -d "$PROJECT" && -x "$PROJECT/venv/bin/python" && -x "$PROJECT/venv/bin/alembic" ]] || fail "Control Center runtime missing"
for c in systemctl runuser psql pg_dump netplan python3 curl; do command -v "$c" >/dev/null || fail "required command missing: $c"; done
for f in \
  payload/app/main.py \
  payload/migrations/versions/14f0a1400001_dhcp_pxe_network_redirects.py \
  payload/templates/shell-1.4.html payload/templates/services-1.4.html payload/templates/dhcp-1.4.html \
  payload/templates/pxe-1.4.html payload/templates/network-1.4.html payload/templates/shares-1.4.html payload/templates/system-1.4.html \
  payload/static/js/services-1.4.js payload/static/js/dhcp-1.4.js payload/static/js/pxe-1.4.js payload/static/js/network-1.4.js \
  payload/static/js/shares-1.4.js payload/static/js/system-1.4.js payload/static/css/release-1.4.css \
  system/srv-control-release14-agent.service system/srv-control-release14-agent.path \
  system/srv-control-backup-retention.service system/srv-control-backup-retention.path \
  system/srv-control-release14-agent.parts/11a.inc \
  system/srv-control-pxe-probe system/srv-control-backup \
  tests/pxe_contract.py tests/pxe_transport_contract.py tests/pxe_lifecycle_contract.py tests/pxe_backup_contract.py; do
  [[ -s "$RELEASE_DIR/$f" ]] || fail "release file missing: $f"
done

check_parts(){
  local dir="$1"; shift
  local expected actual
  expected="$(printf '%s\n' "$@" | sort)"
  actual="$(find "$RELEASE_DIR/$dir" -maxdepth 1 -type f -name '*.part' -printf '%f\n' | sort)"
  [[ "$actual" == "$expected" ]] || fail "unexpected source parts in $dir; expected=[$(tr '\n' ' ' <<<"$expected")] actual=[$(tr '\n' ' ' <<<"$actual")]"
}
check_parts payload/app/core/release14.parts 00.part 01.part 02.part 03.part 04.part 05.part 06.part 07.part
check_parts payload/app/routers/release14.parts 00.part 01.part 02.part 03.part
check_parts system/srv-control-release14-agent.parts 00.part 01.part 02.part 03.part 04.part 05.part 06.part 07.part 08.part 09.part 10.part 11.part 12.part

CURRENT="$(python3 - <<'PY'
import json
from pathlib import Path
try: print(json.loads(Path('/var/lib/srv-control/release.json').read_text()).get('version',''))
except Exception: print('')
PY
)"
[[ "$CURRENT" == 1.3.* ]] || fail "release 1.4.0 requires installed 1.3.x; current=${CURRENT:-unknown}"
runuser -u srv-control -- psql -d srv_control -Atqc 'SELECT 1' | grep -qx 1 || fail "srv_control database unavailable"
REV="$(runuser -u srv-control -- env PYTHONPATH="$PROJECT" PYTHONDONTWRITEBYTECODE=1 "$PROJECT/venv/bin/alembic" -c "$PROJECT/alembic.ini" current 2>/dev/null || true)"
grep -q '13f0a1300001' <<<"$REV" || fail "database is not at the 1.3 schema head: $REV"

tmp_core="$(mktemp)"; tmp_router="$(mktemp)"; tmp_agent="$(mktemp)"
trap 'rm -f "$tmp_core" "$tmp_router" "$tmp_agent"' EXIT
cat "$RELEASE_DIR"/payload/app/core/release14.parts/{00,01,02,03,04,05,06,07}.part > "$tmp_core"
cat "$RELEASE_DIR"/payload/app/routers/release14.parts/{00,01,02,03}.part > "$tmp_router"
cat "$RELEASE_DIR"/system/srv-control-release14-agent.parts/{00,01,02,03,04,05,06,07,08,09,10,11}.part \
    "$RELEASE_DIR/system/srv-control-release14-agent.parts/11a.inc" \
    "$RELEASE_DIR/system/srv-control-release14-agent.parts/12.part" > "$tmp_agent"
"$PROJECT/venv/bin/python" -m py_compile \
  "$RELEASE_DIR/payload/app/main.py" "$tmp_core" "$tmp_router" \
  "$RELEASE_DIR/payload/migrations/versions/14f0a1400001_dhcp_pxe_network_redirects.py" \
  "$tmp_agent" "$RELEASE_DIR/system/srv-control-pxe-probe" "$RELEASE_DIR/system/srv-control-backup" \
  || fail "Python syntax check failed"
python3 "$RELEASE_DIR/tests/pxe_contract.py" || fail "PXE firmware/safety contract failed"
python3 "$RELEASE_DIR/tests/pxe_transport_contract.py" || fail "PXE transport contract failed"
python3 "$RELEASE_DIR/tests/pxe_lifecycle_contract.py" || fail "PXE lifecycle contract failed"
python3 "$RELEASE_DIR/tests/pxe_backup_contract.py" || fail "PXE backup/restore contract failed"
for f in apply.sh rollback.sh acceptance.sh preflight.sh; do bash -n "$RELEASE_DIR/$f" || fail "shell syntax failed: $f"; done
FREE_KB="$(df -Pk "$PROJECT" | awk 'NR==2{print $4}')"
(( FREE_KB >= 1048576 )) || fail "less than 1 GiB free on project filesystem"
[[ -x /usr/local/libexec/srv-control-backup ]] || fail "backup worker missing"
echo "PREFLIGHT PASS: current=$CURRENT db=13f0a1300001 PXE-contracts=firmware+transport+lifecycle+backup"
