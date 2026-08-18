#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${RELEASE_DIR}/../.." && pwd -P)"
BASE_RELEASE="${REPO_ROOT}/releases/2.1.1"
STATE_DIR="/var/lib/srv-control"
RELEASE_META="${STATE_DIR}/release.json"
CANONICAL_UNIT="srv-control-minecraft-bedrock.service"

fail(){ printf 'PREFLIGHT 2.1.2 FAIL: %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" == "0" ]] || fail "must run as root"
[[ -d "$PROJECT" ]] || fail "Control Center project is missing: $PROJECT"
[[ -f "$PROJECT/templates/minecraft.html" ]] || fail "Minecraft template is missing"
[[ -d "$PROJECT/static/js" ]] || fail "Control Center static/js directory is missing"
[[ -s "$RELEASE_META" ]] || fail "release metadata is missing"

SOURCE_VERSION="$(python3 - "$RELEASE_META" <<'PY'
import json,pathlib,sys
try: data=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
except Exception: data={}
print(str(data.get('version') or ''))
PY
)"
case "$SOURCE_VERSION" in
    1.3.8|2.0.0|2.1.0|2.1.1) ;;
    *) fail "unsupported source version: ${SOURCE_VERSION:-missing}" ;;
esac

for path in \
    "$BASE_RELEASE/preflight-2.1.1.sh" \
    "$BASE_RELEASE/apply-2.1.1.sh" \
    "$BASE_RELEASE/rollback-2.1.1.sh" \
    "$RELEASE_DIR/system/srv-control-minecraft-dispatch" \
    "$RELEASE_DIR/system/srv-control-minecraft-ui-status-patch" \
    "$RELEASE_DIR/payload/static/js/minecraft-status-2.1.2.js"
do
    [[ -s "$path" ]] || fail "required release file is missing: $path"
done

python3 -m py_compile \
    "$RELEASE_DIR/system/srv-control-minecraft-dispatch" \
    "$RELEASE_DIR/system/srv-control-minecraft-ui-status-patch"

systemctl cat srv-control.service >/dev/null 2>&1 || fail "srv-control.service is missing"
[[ "$(systemctl show srv-control.service -p NoNewPrivileges --value)" == "yes" ]] \
    || fail "Control Center NoNewPrivileges sandbox must remain enabled"
systemctl cat "$CANONICAL_UNIT" >/dev/null 2>&1 || fail "$CANONICAL_UNIT is missing"
runtime="$(systemctl show "$CANONICAL_UNIT" -p WorkingDirectory --value)"
[[ -n "$runtime" && -d "$runtime" && -f "$runtime/bedrock_server" ]] \
    || fail "canonical Bedrock WorkingDirectory is invalid: ${runtime:-missing}"

if [[ "$SOURCE_VERSION" != "2.1.1" ]]; then
    bash "$BASE_RELEASE/preflight-2.1.1.sh" "$PROJECT" "$REMOTE_SHA"
else
    [[ -x /usr/local/sbin/srv-control-minecraft ]] || fail "2.1.1 public Minecraft helper is missing"
    [[ -x /usr/local/libexec/srv-control-minecraft-agent ]] || fail "Minecraft privileged agent is missing"
fi

printf 'PREFLIGHT 2.1.2 PASS: source=%s canonical runtime=%s; stopped-state status repair is safe to apply\n' "$SOURCE_VERSION" "$runtime"
