#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${RELEASE_DIR}/../.." && pwd -P)"
BASE_RELEASE="${REPO_ROOT}/releases/2.0.0"
SYSTEM="${RELEASE_DIR}/system"
STATE_DIR="/var/lib/srv-control"
RELEASE_META="${STATE_DIR}/release.json"

fail(){ printf 'PREFLIGHT 2.1.0 FAIL: %s\n' "$*" >&2; exit 1; }
warn(){ printf 'PREFLIGHT 2.1.0 WARN: %s\n' "$*" >&2; }

[[ "$(id -u)" -eq 0 ]] || fail "must run as root"
[[ -d "$PROJECT" ]] || fail "Control Center project is missing: $PROJECT"
[[ -s "$RELEASE_META" ]] || fail "installed release metadata is missing"
[[ -x "$SYSTEM/srv-control-minecraft-normalize" || -s "$SYSTEM/srv-control-minecraft-normalize" ]] || fail "Minecraft normalizer is missing"
[[ -s "$SYSTEM/srv-control-minecraft-dispatch" ]] || fail "Minecraft canonical dispatcher is missing"
[[ -s "$BASE_RELEASE/preflight-2.0.0.sh" ]] || fail "published 2.0.0 preflight is missing"
[[ -s "$BASE_RELEASE/apply-2.0.0.sh" ]] || fail "published 2.0.0 apply is missing"
[[ -s "$BASE_RELEASE/acceptance-2.0.0.sh" ]] || fail "published 2.0.0 acceptance is missing"
[[ -s "$BASE_RELEASE/rollback-2.0.0.sh" ]] || fail "published 2.0.0 rollback is missing"

python3 - "$RELEASE_META" <<'PY'
import json,pathlib,re,sys
path=pathlib.Path(sys.argv[1])
data=json.loads(path.read_text(encoding='utf-8'))
version=str(data.get('version') or '')
match=re.fullmatch(r'(\d+)\.(\d+)\.(\d+)',version)
if not match:
    raise SystemExit(f'unsupported installed version: {version!r}')
current=tuple(map(int,match.groups()))
# Real production may still be 1.3.8 while main already publishes 2.0.0.
# 2.1.0 therefore accepts the proven direct path from 1.3.8 and the normal
# upgrade path from 2.0.0. Earlier 1.x builds must first reach the proven 1.3.8 baseline.
if current not in {(1,3,8),(2,0,0)}:
    raise SystemExit(f'unsupported 2.1.0 upgrade source: {version}; expected 1.3.8 or 2.0.0')
print('2.1.0 UPGRADE SOURCE PASS:',version)
PY

# Reuse the frozen/published 2.0 prerequisite contract. This does not modify
# 2.0.0; it proves that a direct 1.3.8 -> 2.1.0 transition can safely carry all
# 2.0 platform changes before Minecraft normalization.
bash "$BASE_RELEASE/preflight-2.0.0.sh" "$PROJECT" "$REMOTE_SHA"

python3 -m py_compile \
    "$SYSTEM/srv-control-minecraft-normalize" \
    "$SYSTEM/srv-control-minecraft-dispatch"

# Audit is intentionally non-blocking for service ownership. 2.1.0 exists to
# normalize a live unmanaged/legacy Bedrock process. Ambiguous multiple runtime
# or process states remain blocking because automatic conversion would be unsafe.
if audit="$($SYSTEM/srv-control-minecraft-normalize audit 2>&1)"; then
    printf '%s\n' "$audit"
else
    printf '%s\n' "$audit" >&2
    if grep -Eq 'multiple Bedrock runtime directories|multiple bedrock_server processes|multiple offline Bedrock runtimes' <<<"$audit"; then
        fail "Minecraft topology is ambiguous and cannot be normalized automatically"
    fi
    warn "Minecraft audit is unhealthy; apply will attempt only non-destructive service normalization"
fi

printf 'PREFLIGHT 2.1.0 PASS: source supported; 2.0 carry-forward proven; Minecraft normalization staged; sha=%s\n' "$REMOTE_SHA"
