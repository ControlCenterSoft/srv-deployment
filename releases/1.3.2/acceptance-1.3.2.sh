#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE="${SCRIPT_DIR}/acceptance.sh"
[[ -r "$SOURCE" ]] || { echo "ACCEPTANCE 1.3.2 FAIL: source acceptance.sh missing" >&2; exit 1; }

PROJECT="${1:-/opt/srv-control}"
TMP="$(mktemp "${TMPDIR:-/tmp}/srvcc-acceptance-1.3.2.XXXXXX.sh")"
STATUS_TMP="$(mktemp "${TMPDIR:-/tmp}/srvcc-minecraft-legacy-status.XXXXXX.json")"
cleanup() { rm -f -- "$TMP" "$STATUS_TMP"; }
trap cleanup EXIT
fail() { printf 'ACCEPTANCE 1.3.2 FAIL: %s\n' "$*" >&2; exit 1; }

python3 - "$SOURCE" "$TMP" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1])
target = Path(sys.argv[2])
text = source.read_text(encoding="utf-8")

if 'RELEASE_ID="1.3.0"' not in text or 'RELEASE_VERSION="1.3.0"' not in text:
    raise SystemExit("acceptance 1.3.2 release anchors missing")
text = text.replace("1.3.0", "1.3.2")

cache_needle = '    [[ -s "$restored_conf" && -s "$restored_sam" ]] || fail "isolated restored domain is incomplete"\n'
cache_insert = cache_needle + '    mkdir -p -- "$restored/cache"\n'
if '    mkdir -p -- "$restored/cache"\n' in text:
    patched = text
elif cache_needle in text:
    patched = text.replace(cache_needle, cache_insert, 1)
else:
    raise SystemExit("acceptance cache hotfix anchor not found; refusing unsafe patch")

sid_needle = """    restored_sid="$(ldbsearch -H "$restored_sam" -b '' -s base objectSid 2>/dev/null | awk '/^objectSid: /{print $2; exit}')"\n    [[ "$restored_sid" == "$live_sid" ]] || fail "restored domain SID mismatch"\n"""
sid_replace = """    restored_base_dn="$(ldbsearch -H "$restored_sam" -b '' -s base defaultNamingContext 2>/dev/null | awk -F': ' '/^defaultNamingContext: /{print $2; exit}')"\n    [[ -n "$restored_base_dn" ]] || fail "restored domain naming context missing"\n    restored_sid="$(ldbsearch -H "$restored_sam" -b "$restored_base_dn" -s base objectSid 2>/dev/null | awk '/^objectSid: /{print $2; exit}')"\n    [[ -n "$restored_sid" ]] || fail "restored domain SID missing"\n    [[ "$restored_sid" == "$live_sid" ]] || fail "restored domain SID mismatch"\n"""
if '    restored_base_dn="$(ldbsearch -H "$restored_sam" -b \'\' -s base defaultNamingContext' in patched:
    pass
elif sid_needle in patched:
    patched = patched.replace(sid_needle, sid_replace, 1)
else:
    raise SystemExit("acceptance SID hotfix anchor not found; refusing unsafe patch")

target.write_text(patched, encoding="utf-8")
PY

chmod 0700 "$TMP"
bash "$TMP" "$@"

# 1.3.2 Minecraft contract checks.
grep -q 'minecraft_legacy_router' "$PROJECT/app/main.py" || fail "legacy Minecraft router is not registered"
grep -q 'BASE = "/api/v1/minecraft/legacy"' "$PROJECT/static/js/minecraft.js" || fail "new Minecraft UI is not using legacy backend"
grep -q 'стабильный backend' "$PROJECT/templates/minecraft.html" || fail "new Minecraft template missing"

for helper in \
    /usr/local/sbin/srv-control-minecraft \
    /usr/local/sbin/srv-control-minecraft-players \
    /usr/local/sbin/srv-control-minecraft-worlds \
    /usr/local/sbin/srv-control-minecraft-restore \
    /usr/local/sbin/srv-control-minecraft-live
do
    [[ -x "$helper" ]] || fail "required proven Minecraft helper missing: $helper"
done

runuser -u srv-control -- /usr/bin/sudo -n /usr/local/sbin/srv-control-minecraft status > "$STATUS_TMP" \
    || fail "legacy Minecraft status helper is not callable by srv-control"
python3 - "$STATUS_TMP" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
try:
    data = json.loads(p.read_text(encoding='utf-8'))
except Exception as exc:
    raise SystemExit(f'invalid legacy Minecraft status JSON: {exc}')
if not isinstance(data, dict) or data.get('ok') is not True:
    raise SystemExit(f'legacy Minecraft status did not return ok=true: {data!r}')
print('LEGACY MINECRAFT STATUS PASS:', data.get('version'), data.get('level_name'), data.get('active'))
PY

if systemctl cat minecraft-update.timer >/dev/null 2>&1; then
    systemctl is-enabled --quiet minecraft-update.timer || fail "legacy minecraft-update.timer is not enabled"
else
    fail "legacy minecraft-update.timer is missing"
fi

if systemctl is-enabled --quiet srv-control-minecraft-auto-update.timer 2>/dev/null; then
    fail "conflicting 1.3.x Minecraft auto-update timer is still enabled"
fi

/usr/sbin/visudo -cf /etc/sudoers.d/srv-control-minecraft-legacy >/dev/null \
    || fail "legacy Minecraft sudoers validation failed"

printf 'ACCEPTANCE 1.3.2 MINECRAFT PASS: proven backend active, update path restored\n'
