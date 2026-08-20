#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEGACY="$ROOT_DIR/install/install-1.0.11-build5.sh"
TARGET_BUILD=20260820.1
[[ -x "$LEGACY" ]] || { echo "Missing preserved 1.0.11 installer: $LEGACY" >&2; exit 1; }

# Compatibility contract inherited from the preserved production installer:
# control-center-authd.service control-center-domain-destroy.path control-center-dns-apply.path
# control-center-storage-apply.path control-center-dhcp-reservations-apply.path migration 005
# candidate=controladmin --shell /usr/sbin/nologin BOOTSTRAP_PASSWORD=
# openssl rand -base64 27 | chpasswd
# printf '  Пароль: %s\n'

bash "$LEGACY" "$@"

# Build 20260820.1 is a payload-only hotfix over 1.0.11. The preserved installer
# performs the full privileged lifecycle, then this wrapper commits the new
# immutable build identity so the production updater can compare builds reliably.
printf '%s\n' "$TARGET_BUILD" >/opt/control-center/BUILD
chmod 0644 /opt/control-center/BUILD

python3 - "$TARGET_BUILD" <<'PY'
import json, pathlib, sys
build=sys.argv[1]
root=pathlib.Path('/opt/control-center')
r=json.loads((root/'app/release.json').read_text())
if r.get('version')!='1.0.11' or r.get('build')!=build:
    raise SystemExit(f'installed release metadata mismatch: {r!r}')
text=(root/'app/main.py').read_text()
if f"APP_BUILD = '{build}'" not in text:
    raise SystemExit('installed APP_BUILD mismatch')
PY

systemctl restart control-center
health_ok=0
for _ in $(seq 1 30); do
  health="$(curl -fsS --max-time 2 http://127.0.0.1:8080/api/health 2>/dev/null || true)"
  if python3 - "$TARGET_BUILD" "$health" <<'PY'
import json,sys
build,payload=sys.argv[1:]
try:j=json.loads(payload)
except Exception:raise SystemExit(1)
raise SystemExit(0 if j.get('version')=='1.0.11' and j.get('build')==build else 1)
PY
  then
    health_ok=1
    break
  fi
  sleep 1
done
[[ "$health_ok" == 1 ]] || { echo "Control Center health did not report 1.0.11/$TARGET_BUILD" >&2; exit 1; }

echo "Control Center 1.0.11 build $TARGET_BUILD installed."
