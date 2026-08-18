#!/usr/bin/env bash
set -Eeuo pipefail
umask 027
PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$RELEASE_DIR/../.." && pwd -P)"
STATE=/var/lib/srv-control
META="$STATE/release.json"
fail(){ echo "ACCEPTANCE 2.1.4 FAIL: $*" >&2; exit 1; }
[[ -s "$META" ]] || fail "release metadata missing"
python3 - "$META" "$REMOTE_SHA" <<'PY'
import json,pathlib,sys
p=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
assert p.get('version') == '2.1.4',p
assert p.get('release_id') == '2.1.4',p
if sys.argv[2] != 'unknown': assert p.get('git_sha') == sys.argv[2],(p,sys.argv[2])
print('RELEASE MARKER PASS:',p.get('version'))
PY
curl -fsS --max-time 10 http://127.0.0.1:8876/api/v1/health >/tmp/control-center-2.1.4-health.json \
  || fail "Control Center health endpoint unavailable"
python3 - /tmp/control-center-2.1.4-health.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
assert p.get('ok') is True,p
release=(p.get('data') or {}).get('release') or {}
assert release.get('version') == '2.1.4',release
print('CONTROL CENTER HEALTH PASS:',release.get('version'))
PY
rm -f /tmp/control-center-2.1.4-health.json
# Rebuild the exact clean-install application image without touching production.
tmp="$(mktemp -d /var/tmp/control-center-accept-2.1.4.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
python3 "$REPO_ROOT/installer/build-install-payload.py" \
  "$REPO_ROOT" "$REPO_ROOT/installer/install-profile.json" "$tmp/payload" >/tmp/control-center-2.1.4-build.json \
  || fail "install payload builder failed"
python3 - "$tmp/payload" <<'PY'
import pathlib,sys
root=pathlib.Path(sys.argv[1])
required=['app/main.py','requirements.lock','alembic.ini','templates/login.html','templates/minecraft.html','static/js/minecraft.js','static/js/minecraft-status-2.1.2.js']
for rel in required:
    p=root/rel
    assert p.is_file() and p.stat().st_size>0,rel
router=(root/'app/routers/minecraft_legacy.py').read_text(encoding='utf-8')
assert '["/usr/bin/sudo", "-n", str(helper), *args]' not in router
template=(root/'templates/minecraft.html').read_text(encoding='utf-8')
assert '/static/js/minecraft-status-2.1.2.js' in template
print('CONSOLIDATED CLEAN-INSTALL PAYLOAD PASS')
PY
rm -rf "$tmp" /tmp/control-center-2.1.4-build.json
trap - EXIT
# Validate the regression guard that prevents nginx from mistaking its own
# package-default listener for an external port-80 conflict.
grep -Fq 'systemctl stop nginx.service' "$REPO_ROOT/installer/install.sh" || fail "nginx self-listener guard missing"
grep -Fq 'proxy=f"http://127.0.0.1:{web_port}/api/v1/health"' "$REPO_ROOT/installer/install.sh" || fail "public reverse-proxy acceptance missing"
grep -Fq 'system_baseline' "$REPO_ROOT/installer/install-system-admin.sh" || fail "system baseline installer contract missing"
# Keep the Minecraft stabilization gained in 2.1.2 when it exists on this host.
if [[ -x /usr/local/sbin/srv-control-minecraft ]]; then
  /usr/local/sbin/srv-control-minecraft status >/tmp/control-center-2.1.4-minecraft.json \
    || fail "Minecraft status helper failed"
  python3 - /tmp/control-center-2.1.4-minecraft.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
assert p.get('ok') is True,p
assert p.get('state') in {'running','degraded','stopped'},p
print('MINECRAFT STATUS CONTRACT PASS:',p.get('state'))
PY
  rm -f /tmp/control-center-2.1.4-minecraft.json
fi
echo "ACCEPTANCE 2.1.4 PASS: current runtime healthy; clean-install payload and nginx entrypoint regression accepted"
