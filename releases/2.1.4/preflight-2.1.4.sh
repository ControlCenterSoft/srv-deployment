#!/usr/bin/env bash
set -Eeuo pipefail
umask 027
PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$RELEASE_DIR/../.." && pwd -P)"
STATE=/var/lib/srv-control
META="$STATE/release.json"
fail(){ echo "PREFLIGHT 2.1.4 FAIL: $*" >&2; exit 1; }
[[ -d "$PROJECT" ]] || fail "Control Center project missing"
[[ -s "$META" ]] || fail "release metadata missing"
source_version="$(python3 - "$META" <<'PY'
import json,pathlib,sys
try: data=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
except Exception: data={}
print(data.get('version') or '')
PY
)"
case "$source_version" in
  1.3.8|2.0.0|2.1.0|2.1.1|2.1.2) ;;
  *) fail "unsupported source version: ${source_version:-missing}" ;;
esac
[[ -s "$REPO_ROOT/installer/install-profile.json" ]] || fail "install profile missing"
[[ -s "$REPO_ROOT/installer/build-install-payload.py" ]] || fail "install payload builder missing"
[[ -s "$REPO_ROOT/installer/install.sh" ]] || fail "clean installer missing"
[[ -s "$REPO_ROOT/installer/install-system-admin.sh" ]] || fail "system-admin installer missing"
bash -n "$REPO_ROOT/installer/install.sh"
bash -n "$REPO_ROOT/installer/install-system-admin.sh"
python3 -m py_compile "$REPO_ROOT/installer/build-install-payload.py"
if [[ "$source_version" != "2.1.2" ]]; then
  bash "$REPO_ROOT/releases/2.1.2/preflight-2.1.2.sh" "$PROJECT" "$REMOTE_SHA"
fi
echo "PREFLIGHT 2.1.4 PASS: source=$source_version; consolidated clean-install contract present"
