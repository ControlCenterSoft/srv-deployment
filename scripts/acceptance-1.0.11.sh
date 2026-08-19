#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=/opt/control-center
[[ "$(tr -d '[:space:]' <"$ROOT/VERSION")" == '1.0.11' ]]
[[ "$(tr -d '[:space:]' <"$ROOT/BUILD")" == '20260819.5' ]]
PORT=$(sudo sed -n 's/^CONTROL_CENTER_PORT=//p' /etc/control-center/web.env | head -1); PORT=${PORT:-8080}
SSL=$(sudo sed -n 's/^CONTROL_CENTER_SSL=//p' /etc/control-center/web.env | head -1); SSL=${SSL:-0}
SCHEME=http; CURL=(-fsS --max-time 8)
if [[ "$SSL" == 1 || "$SSL" == true ]]; then SCHEME=https; CURL=(-kfsS --max-time 8); fi
BASE="$SCHEME://127.0.0.1:$PORT"

H=$(curl "${CURL[@]}" "$BASE/api/health")
python3 - "$H" <<'PY'
import json,sys
j=json.loads(sys.argv[1]);assert j['version']=='1.0.11' and j['build']=='20260819.5'
PY
systemctl is-active --quiet control-center
systemctl is-active --quiet control-center-samba-apply.path
systemctl is-enabled --quiet control-center-samba-apply.path
test -x /usr/local/sbin/control-center-samba-apply
test -x /usr/local/sbin/control-center-samba-approve
test "$(stat -c '%U:%G %a' /run/control-center)" = 'control-center:control-center 700'
test "$(stat -c '%U:%G %a' /run/control-center-root)" = 'root:root 700'

after_migration=$(sudo -u control-center psql -d control_center -Atqc "select version from control_center.schema_migrations order by version desc limit 1" 2>/dev/null || true)
if [[ -n "$after_migration" ]]; then [[ "$after_migration" == 004 ]]; fi

S=$(curl "${CURL[@]}" "$BASE/api/samba/status")
python3 - "$S" <<'PY'
import json,sys
j=json.loads(sys.argv[1]);assert j['version']=='1.0.11';assert j['approval_required'] is True;assert j['password_persisted'] is False
PY
PROVISIONED=$(python3 - "$S" <<'PY'
import json,sys
print('1' if json.loads(sys.argv[1]).get('provisioned') else '0')
PY
)
if [[ "$PROVISIONED" == 1 ]]; then
  HEALTH=$(curl "${CURL[@]}" -X POST "$BASE/api/samba/health")
  python3 - "$HEALTH" <<'PY'
import json,sys
j=json.loads(sys.argv[1]);assert j['healthy'] is True,(j.get('state'),j.get('checks'))
PY
  systemctl is-active --quiet samba-ad-dc.service
  sudo samba-tool testparm >/dev/null
  sudo samba-tool ntacl sysvolcheck >/dev/null
else
  PLAN=$(curl "${CURL[@]}" -X POST -H 'Content-Type: application/json' -d '{}' "$BASE/api/samba/plan")
  python3 - "$PLAN" <<'PY'
import json,sys
j=json.loads(sys.argv[1]);assert j['plan']['phase']=='production-provision';assert j['plan']['provisioning_enabled'] is True;assert j['plan']['approval_required'] is True;assert j['plan']['password_persisted'] is False
PY
fi

bash -n /usr/local/sbin/control-center-samba-apply
bash -n /usr/local/sbin/control-center-samba-approve
if command -v node >/dev/null 2>&1; then node --check "$ROOT/app/static/release-111.js" >/dev/null; fi

echo 'ACCEPTANCE 1.0.11: PASSED'
