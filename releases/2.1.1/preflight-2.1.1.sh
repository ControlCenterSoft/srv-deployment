#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${RELEASE_DIR}/../.." && pwd -P)"
BASE_RELEASE="${REPO_ROOT}/releases/2.1.0"
SYSTEM="${RELEASE_DIR}/system"
STATE_DIR="/var/lib/srv-control"
RELEASE_META="${STATE_DIR}/release.json"
CANONICAL_UNIT="srv-control-minecraft-bedrock.service"

fail(){ printf 'PREFLIGHT 2.1.1 FAIL: %s\n' "$*" >&2; exit 1; }
warn(){ printf 'PREFLIGHT 2.1.1 WARN: %s\n' "$*" >&2; }

[[ "$(id -u)" -eq 0 ]] || fail "must run as root"
[[ -d "$PROJECT" ]] || fail "Control Center project is missing: $PROJECT"
[[ -s "$RELEASE_META" ]] || fail "installed release metadata is missing"

for command in python3 systemctl ss ps getent useradd usermod groupadd chown chmod install find stat curl; do
    command -v "$command" >/dev/null 2>&1 || fail "required command is missing: $command"
done

for path in \
    "$BASE_RELEASE/preflight-2.1.0.sh" \
    "$BASE_RELEASE/apply-2.1.0.sh" \
    "$BASE_RELEASE/acceptance-2.1.0.sh" \
    "$BASE_RELEASE/rollback-2.1.0.sh" \
    "$BASE_RELEASE/system/srv-control-minecraft-normalize" \
    "$SYSTEM/srv-control-minecraft-permissions" \
    "$SYSTEM/srv-control-minecraft-permissions.service" \
    "$SYSTEM/srv-control-minecraft-bedrock-update" \
    "$SYSTEM/srv-control-minecraft-bedrock-update.service" \
    "$SYSTEM/srv-control-minecraft-bedrock-update.timer" \
    "$SYSTEM/srv-control-minecraft-dispatch"
do [[ -s "$path" ]] || fail "required 2.1.1 payload is missing: $path"; done

SOURCE_VERSION="$(python3 - "$RELEASE_META" <<'PY'
import json,pathlib,re,sys
p=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
version=str(p.get('version') or '')
if not re.fullmatch(r'\d+\.\d+\.\d+',version):
    raise SystemExit(f'unsupported installed version: {version!r}')
if version not in {'1.3.8','2.0.0','2.1.0'}:
    raise SystemExit(f'unsupported 2.1.1 upgrade source: {version}; expected 1.3.8, 2.0.0 or 2.1.0')
print(version)
PY
)" || fail "installed release is not a supported 2.1.1 source"
printf '2.1.1 UPGRADE SOURCE PASS: %s\n' "$SOURCE_VERSION"

# Servers that skipped 2.1.0 must first prove the exact frozen 2.1.0 transition.
# The current production path (2.1.0 -> 2.1.1) is checked below without an
# unnecessary preflight-side restart or backup.
if [[ "$SOURCE_VERSION" != "2.1.0" ]]; then
    bash "$BASE_RELEASE/preflight-2.1.0.sh" "$PROJECT" "$REMOTE_SHA"
else
    systemctl is-enabled --quiet "$CANONICAL_UNIT" || fail "$CANONICAL_UNIT is not enabled"
    systemctl is-active --quiet "$CANONICAL_UNIT" || fail "$CANONICAL_UNIT is not active"
    python3 "$BASE_RELEASE/system/srv-control-minecraft-normalize" audit > /tmp/srvcc-2.1.1-preflight-minecraft.json \
        || { cat /tmp/srvcc-2.1.1-preflight-minecraft.json >&2 || true; fail "2.1.0 canonical Minecraft audit failed"; }
    python3 - /tmp/srvcc-2.1.1-preflight-minecraft.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
assert p.get('ok') is True,p
assert p.get('canonical') is True,p
assert p.get('needs_normalization') is False,p
assert p.get('port_listening') is True,p
assert p.get('world_exists') is True,p
assert len(p.get('pids') or []) == 1,p
print('2.1.0 CANONICAL BASELINE PASS:',p.get('runtime'),p.get('level_name'),p.get('port'))
PY
    rm -f /tmp/srvcc-2.1.1-preflight-minecraft.json
fi

python3 -m py_compile \
    "$SYSTEM/srv-control-minecraft-permissions" \
    "$SYSTEM/srv-control-minecraft-bedrock-update" \
    "$SYSTEM/srv-control-minecraft-dispatch"

# A root-owned canonical service is the exact production condition 2.1.1 is
# designed to harden. Already-unprivileged installations remain idempotently safe.
if systemctl cat "$CANONICAL_UNIT" >/dev/null 2>&1; then
    current_user="$(systemctl show "$CANONICAL_UNIT" -p User --value 2>/dev/null || true)"
    current_group="$(systemctl show "$CANONICAL_UNIT" -p Group --value 2>/dev/null || true)"
    printf 'Minecraft service identity before 2.1.1: user=%s group=%s\n' "${current_user:-root/default}" "${current_group:-root/default}"
fi

python3 - "$PROJECT" "$STATE_DIR" <<'PY'
import shutil,sys
for path in sys.argv[1:]:
    free=shutil.disk_usage(path).free
    if free < 512*1024*1024:
        raise SystemExit(f'less than 512 MiB free at {path}')
    print('DISK PASS:',path,free)
PY

curl -fsS --max-time 10 http://127.0.0.1:8876/api/v1/health >/dev/null \
    || fail "Control Center health endpoint is unavailable before 2.1.1"

printf 'PREFLIGHT 2.1.1 PASS: source=%s; canonical Minecraft healthy; unprivileged ownership and canonical updater hardening staged; sha=%s\n' "$SOURCE_VERSION" "$REMOTE_SHA"
