#!/usr/bin/env bash
set -Eeuo pipefail

RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE="${RELEASE_DIR}/acceptance.sh"
TMP="$(mktemp "${TMPDIR:-/tmp}/srvcc-acceptance-1.3.3.XXXXXX.sh")"
PROJECT="${1:-/opt/srv-control}"
STATUS_TMP="$(mktemp "${TMPDIR:-/tmp}/srvcc-minecraft-legacy-status.XXXXXX.json")"
cleanup(){ rm -f -- "$TMP" "$STATUS_TMP"; }
trap cleanup EXIT
fail(){ printf 'ACCEPTANCE 1.3.3 FAIL: %s\n' "$*" >&2; exit 1; }

python3 - "$SOURCE" "$TMP" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]); dst=Path(sys.argv[2]); text=src.read_text(encoding='utf-8')
if 'RELEASE_ID="1.3.0"' not in text or 'RELEASE_VERSION="1.3.0"' not in text:
    raise SystemExit('1.3.3 acceptance release anchors missing')
text=text.replace('1.3.0','1.3.3')
# 1.3.3 intentionally disables the 1.3 multi-instance auto-update timer. The
# old base acceptance must therefore stop requiring it to be active.
needle='    srv-control-minecraft-auto-update.timer \\\n'
if needle not in text:
    raise SystemExit('1.3.3 acceptance modern timer anchor missing')
text=text.replace(needle,'',1)
# Keep the Samba restore fixes proven during 1.3.1/1.3.2 real-server testing.
cache='    [[ -s "$restored_conf" && -s "$restored_sam" ]] || fail "isolated restored domain is incomplete"\n'
if '    mkdir -p -- "$restored/cache"\n' not in text:
    if cache not in text: raise SystemExit('acceptance cache hotfix anchor missing')
    text=text.replace(cache,cache+'    mkdir -p -- "$restored/cache"\n',1)
sid="""    restored_sid="$(ldbsearch -H "$restored_sam" -b '' -s base objectSid 2>/dev/null | awk '/^objectSid: /{print $2; exit}')"\n    [[ "$restored_sid" == "$live_sid" ]] || fail "restored domain SID mismatch"\n"""
sidr="""    restored_base_dn="$(ldbsearch -H "$restored_sam" -b '' -s base defaultNamingContext 2>/dev/null | awk -F': ' '/^defaultNamingContext: /{print $2; exit}')"\n    [[ -n "$restored_base_dn" ]] || fail "restored domain naming context missing"\n    restored_sid="$(ldbsearch -H "$restored_sam" -b "$restored_base_dn" -s base objectSid 2>/dev/null | awk '/^objectSid: /{print $2; exit}')"\n    [[ -n "$restored_sid" ]] || fail "restored domain SID missing"\n    [[ "$restored_sid" == "$live_sid" ]] || fail "restored domain SID mismatch"\n"""
if 'restored_base_dn=' not in text:
    if sid not in text: raise SystemExit('acceptance SID hotfix anchor missing')
    text=text.replace(sid,sidr,1)
dst.write_text(text,encoding='utf-8')
PY
chmod 0700 "$TMP"
bash "$TMP" "$@"

# Authentication continuity.
[[ -s /var/lib/srv-control/session.key ]] || fail "session.key missing after deployment"

# GitHub automatic-mode contract. The selected mode must survive release apply.
python3 - /var/lib/srv-control/github-update-config.json <<'PY'
import json,pathlib,sys
p=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
assert p.get('mode') in {'automatic','manual'},p
assert isinstance(p.get('interval_minutes'),int) and 1 <= p['interval_minutes'] <= 1440,p
print('GITHUB UPDATE CONFIG PASS:',p.get('mode'),p.get('interval_minutes'))
PY
if python3 - /var/lib/srv-control/github-update-config.json <<'PY'
import json,pathlib,sys
p=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
raise SystemExit(0 if p.get('mode')=='automatic' else 1)
PY
then
    systemctl is-enabled --quiet srvcc-github-agent.timer || fail "automatic GitHub timer is not enabled"
    systemctl is-active --quiet srvcc-github-agent.timer || fail "automatic GitHub timer is not active"
else
    ! systemctl is-enabled --quiet srvcc-github-agent.timer 2>/dev/null || fail "manual GitHub mode unexpectedly has timer enabled"
fi
grep -q 'LAST_FAILED_FINGERPRINT' /usr/local/sbin/srvcc-github-agent || fail "failed-release retry suppression missing"

# Proven primary Minecraft backend and update path.
for helper in \
 /usr/local/sbin/srv-control-minecraft \
 /usr/local/sbin/srv-control-minecraft-players \
 /usr/local/sbin/srv-control-minecraft-worlds \
 /usr/local/sbin/srv-control-minecraft-restore \
 /usr/local/sbin/srv-control-minecraft-live
do [[ -x "$helper" ]] || fail "required proven Minecraft helper missing: $helper"; done

runuser -u srv-control -- /usr/bin/sudo -n /usr/local/sbin/srv-control-minecraft status > "$STATUS_TMP" \
 || fail "legacy Minecraft status helper is not callable by srv-control"
python3 - "$STATUS_TMP" <<'PY'
import json,pathlib,sys
data=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
assert isinstance(data,dict) and data.get('ok') is True,data
print('MINECRAFT STATUS PASS:',data.get('version'),data.get('level_name'),data.get('active'))
PY
systemctl is-enabled --quiet minecraft-update.timer || fail "legacy minecraft-update.timer is not enabled"
systemctl is-active --quiet minecraft-update.timer || fail "legacy minecraft-update.timer is not active"
if systemctl is-enabled --quiet srv-control-minecraft-auto-update.timer 2>/dev/null; then
    fail "conflicting 1.3 multi-instance Minecraft update timer remains enabled"
fi
/usr/sbin/visudo -cf /etc/sudoers.d/srv-control-minecraft-legacy >/dev/null || fail "Minecraft sudoers invalid"

grep -q 'minecraft_legacy_router' "$PROJECT/app/main.py" || fail "legacy Minecraft router is not registered"
grep -q 'BASE = "/api/v1/minecraft/legacy"' "$PROJECT/static/js/minecraft.js" || fail "Minecraft UI is not using legacy backend"

printf 'ACCEPTANCE 1.3.3 PASS: GitHub updater reliable; authentication continuous; Minecraft updater restored\n'
