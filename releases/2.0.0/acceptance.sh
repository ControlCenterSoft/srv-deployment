#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="1.3.0"
RELEASE_VERSION="1.3.0"
BACKUP_DIR="/var/lib/srv-deployment/backups/${REMOTE_SHA}-${RELEASE_ID}"
STATE_DIR="/var/lib/srv-control"

fail() { printf 'ACCEPTANCE FAIL: %s\n' "$*" >&2; exit 1; }

systemctl is-active --quiet srv-control.service || fail "srv-control.service is not active"
for unit in \
    srv-control-system-agent.path \
    srv-control-samba-agent.path \
    srv-control-samba-monitor.timer \
    srv-control-samba-shares-monitor.timer \
    srv-control-minecraft-agent.path \
    srv-control-minecraft-monitor.timer \
    srv-control-minecraft-auto-update.timer \
    srv-control-adguard-monitor.timer
do
    systemctl is-active --quiet "$unit" || fail "$unit is not active"
done

for helper in \
    srv-control-backup srv-control-samba-admin srv-control-samba-agent \
    srv-control-samba-monitor srv-control-samba-shares-monitor \
    srv-control-minecraft-admin srv-control-minecraft-admin-core \
    srv-control-minecraft-agent srv-control-minecraft-monitor \
    srv-control-minecraft-player-admin srv-control-minecraft-update
do
    [[ -x "/usr/local/libexec/$helper" ]] || fail "installed helper missing: $helper"
done
[[ -x /usr/local/sbin/srvcc-github-agent ]] || fail "GitHub updater missing"
[[ -s /etc/pam.d/srv-control ]] || fail "PAM service missing"

before_pid="$(cat "$BACKUP_DIR/state/main-pid.before" 2>/dev/null || true)"
after_pid="$(systemctl show srv-control.service -p MainPID --value)"
[[ -n "$before_pid" && "$before_pid" == "$after_pid" ]] || fail "graceful reload invariant failed"

migration="$(runuser -u srv-control -- psql -d srv_control -Atc 'SELECT version_num FROM alembic_version LIMIT 1;')"
[[ "$migration" == "13f0a1300001" ]] || fail "unexpected database migration head: $migration"
nginx -t >/dev/null 2>&1 || fail "nginx configuration is invalid"

runuser -u srv-control -- env PYTHONPATH="$PROJECT" PYTHONDONTWRITEBYTECODE=1 "$PROJECT/venv/bin/python" - "$REMOTE_SHA" <<'PY'
from __future__ import annotations

import http.client
import json
import sys

from app.core.rbac import (
    FULL_ADMIN_PERMISSION_KEY, MODULES, delete_grant, has_permission,
    is_full_admin, permissions_for, upsert_grant,
)
from app.core.system_auth import COOKIE_NAME, Identity, create_session, resolve_identity

expected_sha=sys.argv[1]

def request(path: str, cookie: str | None = None):
    connection=http.client.HTTPConnection('127.0.0.1',8876,timeout=15)
    headers={}
    if cookie: headers['Cookie']=cookie
    connection.request('GET',path,headers=headers)
    response=connection.getresponse(); body=response.read(); headers=dict(response.getheaders()); status=response.status
    connection.close(); return status,headers,body

status,_,body=request('/api/v1/health')
assert status==200,(status,body[:500])
release=json.loads(body).get('data',{}).get('release',{})
assert release.get('version')=='1.3.0',release
assert release.get('release_id')=='1.3.0',release
assert release.get('git_sha')==expected_sha,release

root=resolve_identity('root','local')
assert root is not None and root.is_admin,root
token,_=create_session(root); cookie=f'{COOKIE_NAME}={token}'
for path in (
    '/', '/ui/dashboard', '/ui/module/system', '/ui/module/access', '/ui/module/services',
    '/ui/module/samba', '/ui/module/shares', '/ui/module/minecraft', '/ui/module/adguard', '/ui/module/torrents',
    '/api/v1/dashboard/metrics', '/api/v1/system/configuration', '/api/v1/access/grants',
    '/api/v1/services', '/api/v1/samba', '/api/v1/shares', '/api/v1/minecraft/instances',
):
    status,_,body=request(path,cookie)
    assert status==200,(path,status,body[:700])

identity=Identity(username='srvcc-13-user',uid=65001,gid=65001,groups=('srvcc-13-group',),auth_source='local',is_admin=False)
ids=[]
try:
    samba=upsert_grant(subject_type='user',subject_name=identity.username,source='local',module='samba',access='write',actor='acceptance')
    ids.append(int(samba['id']))
    assert has_permission(identity,'samba','write') is True
    assert has_permission(identity,'shares','write') is False
    shares=upsert_grant(subject_type='user',subject_name=identity.username,source='local',module='shares',access='write',actor='acceptance')
    ids.append(int(shares['id']))
    assert has_permission(identity,'shares','write') is True
    assert has_permission(identity,'minecraft','write') is False
    admin=upsert_grant(subject_type='user',subject_name=identity.username,source='local',module='samba',access='admin',actor='acceptance')
    ids.append(int(admin['id']))
    assert is_full_admin(identity) is True
    permissions=permissions_for(identity)
    assert permissions[FULL_ADMIN_PERMISSION_KEY]=='admin'
    for module in MODULES:
        assert has_permission(identity,module,'write') is True,(module,permissions)
finally:
    for grant_id in reversed(ids):
        delete_grant(grant_id)

print(json.dumps({'release':release,'samba_write':True,'shares_write':True,'full_admin':True},ensure_ascii=False))
PY

# Pure helper safety tests: no live configuration is changed here.
python3 - <<'PY'
from importlib.machinery import SourceFileLoader
from pathlib import Path
import tempfile

samba=SourceFileLoader('srvcc_samba_admin','/usr/local/libexec/srv-control-samba-admin').load_module()
assert samba.share_name('Public_01')=='Public_01'
for invalid in ('Общая','../bad','bad share','/root'):
    try: samba.share_name(invalid)
    except RuntimeError: pass
    else: raise AssertionError(f'invalid share name accepted: {invalid!r}')
registry={'schema_version':1,'shares':[{
    'name':'SmokeShare','path':'/srv/shares/SmokeShare','comment':'Проверка',
    'browseable':False,'subjects':[{'type':'everyone','access':'read'}],'quota':{},
}]}
rendered=samba.render_shares(registry)
assert '[SmokeShare]' in rendered and 'browseable = no' in rendered and 'valid users = Everyone' in rendered

mc=SourceFileLoader('srvcc_mc_admin','/usr/local/libexec/srv-control-minecraft-admin-core').load_module()
assert mc.instance_id('test_01')=='test_01'
try: mc.instance_id('../bad')
except RuntimeError: pass
else: raise AssertionError('unsafe Minecraft instance id accepted')
with tempfile.TemporaryDirectory() as td:
    root=Path(td); one=root/'one'; one.mkdir(); (one/'server.properties').write_text('server-port=19132\nserver-portv6=19133\n',encoding='utf-8')
    registry={'schema_version':1,'instances':[{'id':'one','working_directory':str(one),'server_port':19132,'server_portv6':19133}]}
    try: mc.validate_ports(registry,'two',19132,19134)
    except RuntimeError: pass
    else: raise AssertionError('Minecraft port collision not detected')
PY

# If this host is an actual AD DC, perform read-only health checks and create a
# real migration backup. Restore is tested to an isolated directory only; the
# restored Samba instance is never started.
role="$(testparm -s --parameter-name='server role' 2>/dev/null || true)"
smoke_backup_id=""
smoke_archive=""
restore_tmp=""
cleanup_domain_smoke() {
    [[ -n "$restore_tmp" && -d "$restore_tmp" ]] && rm -rf -- "$restore_tmp" || true
    [[ -n "$smoke_archive" ]] && rm -f -- "$smoke_archive" || true
    [[ -n "$smoke_backup_id" ]] && rm -f -- "$STATE_DIR/domain-backups/${smoke_backup_id}.json" || true
}
trap cleanup_domain_smoke EXIT

if [[ "${role,,}" == *"active directory domain controller"* ]]; then
    command -v samba-tool >/dev/null 2>&1 || fail "samba-tool missing on provisioned DC"
    command -v ldbsearch >/dev/null 2>&1 || fail "ldbsearch missing on provisioned DC"
    samba-tool dbcheck --cross-ncs >/dev/null || fail "live Samba dbcheck failed"
    testparm -s --suppress-prompt >/dev/null 2>&1 || fail "live Samba testparm failed"

    smoke_output="$(printf '%s\n' '{"action":"samba-backup-create","actor":"acceptance","payload":{"mode":"domain-config"}}' | /usr/local/libexec/srv-control-samba-admin)" \
        || fail "Samba migration backup smoke failed"
    readarray -t backup_values < <(python3 - <<'PY' "$smoke_output"
import json,sys
outer=json.loads(sys.argv[1]); assert outer.get('ok') is True,outer
meta=json.loads(outer['detail']); print(meta['id']); print(meta['archive']); print(meta['sha256'])
PY
)
    smoke_backup_id="${backup_values[0]}"
    smoke_archive="$STATE_DIR/domain-backups/${backup_values[1]}"
    expected_sha="${backup_values[2]}"
    [[ -s "$smoke_archive" ]] || fail "Samba migration archive missing"
    actual_sha="$(sha256sum "$smoke_archive" | awk '{print $1}')"
    [[ "$actual_sha" == "$expected_sha" ]] || fail "Samba migration archive checksum mismatch"

    restore_tmp="$(mktemp -d /var/lib/srv-control/domain-acceptance.XXXXXX)"
    tar -xf "$smoke_archive" -C "$restore_tmp" manifest.json domain control
    official_backup="$(find "$restore_tmp/domain" -maxdepth 1 -type f -print -quit)"
    [[ -s "$official_backup" ]] || fail "official Samba backup component missing"
    live_realm="$(testparm -s --parameter-name=realm 2>/dev/null | tr '[:lower:]' '[:upper:]')"
    live_sid="$(python3 - "$smoke_archive" <<'PY'
import json,sys,tarfile
with tarfile.open(sys.argv[1],'r:*') as tar:
    data=json.load(tar.extractfile('manifest.json'))
print(data.get('domain',{}).get('sid') or '')
PY
)"
    [[ -n "$live_sid" ]] || fail "domain SID missing from migration manifest"
    restored="$restore_tmp/restored"
    samba-tool domain backup restore --backup-file="$official_backup" --newservername=SRVCCRT --targetdir="$restored" >/dev/null \
        || fail "isolated Samba backup restore failed"
    restored_conf="$(find "$restored" -type f -name smb.conf -print -quit)"
    restored_sam="$(find "$restored" -type f -name sam.ldb -print -quit)"
    [[ -s "$restored_conf" && -s "$restored_sam" ]] || fail "isolated restored domain is incomplete"
    testparm -s --suppress-prompt "$restored_conf" >/dev/null 2>&1 || fail "isolated restored smb.conf invalid"
    restored_realm="$(testparm -s --suppress-prompt --parameter-name=realm "$restored_conf" 2>/dev/null | tr '[:lower:]' '[:upper:]')"
    [[ "$restored_realm" == "$live_realm" ]] || fail "restored domain realm mismatch"
    restored_sid="$(ldbsearch -H "$restored_sam" -b '' -s base objectSid 2>/dev/null | awk '/^objectSid: /{print $2; exit}')"
    [[ "$restored_sid" == "$live_sid" ]] || fail "restored domain SID mismatch"
fi

if grep -R -n -i -E 'пока не работает|будет реализовано|future release only|будет включено' "$PROJECT/templates" "$PROJECT/static" >/dev/null 2>&1; then
    fail "temporary placeholder text found in installed UI"
fi

printf 'ACCEPTANCE PASS: release=%s sha=%s\n' "$RELEASE_VERSION" "$REMOTE_SHA"
