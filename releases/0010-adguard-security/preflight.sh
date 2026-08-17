#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="0010-adguard-security"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${RELEASE_DIR}/../.." && pwd -P)"
PAYLOAD="${REPO_ROOT}/installer/payload"
SYSTEM_DIR="${REPO_ROOT}/installer/system"

fail() { printf 'PREFLIGHT FAIL: %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || fail "must run as root"
[[ -d "$PROJECT" ]] || fail "project directory missing: $PROJECT"
[[ -x "$PROJECT/venv/bin/python" ]] || fail "project virtualenv is missing"
[[ -x "$REPO_ROOT/deploy/reload-srv-control.sh" ]] || fail "graceful reload helper missing"
[[ -x "$REPO_ROOT/installer/install-system-admin.sh" ]] || fail "system admin installer missing"

for command in systemctl python3; do command -v "$command" >/dev/null 2>&1 || fail "$command is required"; done
for path in app/core/auth.py app/core/system_admin.py app/routers/api.py templates/system.html static/js/system.js; do [[ -s "$PAYLOAD/$path" ]] || fail "payload file missing: $path"; done
for path in srv-control-system-agent srv-control-adguard-monitor srv-control-adguard-monitor.service srv-control-adguard-monitor.timer; do [[ -s "$SYSTEM_DIR/$path" ]] || fail "system payload missing: $path"; done

python3 - "$PAYLOAD/app/core/auth.py" "$PAYLOAD/app/core/system_admin.py" "$PAYLOAD/app/routers/api.py" "$SYSTEM_DIR/srv-control-system-agent" "$SYSTEM_DIR/srv-control-adguard-monitor" <<'PY'
import pathlib, sys
for value in sys.argv[1:]:
    path = pathlib.Path(value)
    compile(path.read_text(encoding="utf-8"), str(path), "exec")
PY

grep -Fq 'LOGIN_FAILURE_LIMIT = 5' "$PAYLOAD/app/core/auth.py" || fail "login throttling missing"
grep -Fq 'service-connect-adguard-vpn-socks' "$PAYLOAD/app/core/system_admin.py" || fail "safe AdGuard action missing"
grep -Fq 'include_actions=authenticated' "$PAYLOAD/app/routers/api.py" || fail "protected action history missing"
grep -Fq 'id="systemActionPanel"' "$PAYLOAD/templates/system.html" || fail "protected action history UI missing"
grep -Fq 'adguardvpn-cli login' "$PAYLOAD/templates/system.html" || fail "local AdGuard login instruction missing"

systemctl is-active --quiet srv-control.service || fail "srv-control.service is not active before deployment"
exec_start="$(systemctl show srv-control.service -p ExecStart --value 2>/dev/null || true)"
[[ "$exec_start" == *"--workers 2"* ]] || fail "release requires multi-worker service from 0.4.0"
printf 'PREFLIGHT PASS: release=%s sha=%s\n' "$RELEASE_ID" "$REMOTE_SHA"
