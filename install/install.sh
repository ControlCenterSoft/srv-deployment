#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEGACY="$ROOT_DIR/install/install-1.0.11-build5.sh"
TARGET_BUILD=20260820.2
TMP=""
[[ -x "$LEGACY" ]] || { echo "Missing preserved 1.0.11 installer: $LEGACY" >&2; exit 1; }
cleanup_wrapper(){ [[ -n "$TMP" ]] && rm -f "$TMP" || true; }
trap cleanup_wrapper EXIT

# Compatibility contract inherited from the preserved production installer:
# control-center-authd.service control-center-domain-destroy.path control-center-dns-apply.path
# control-center-storage-apply.path control-center-dhcp-reservations-apply.path migration 005
# candidate=controladmin --shell /usr/sbin/nologin BOOTSTRAP_PASSWORD=
# openssl rand -base64 27 | chpasswd
# printf '  Пароль: %s\n'

# Keep the proven 1.0.11 installer logic, but execute a same-directory temporary
# copy whose build identity is consistently advanced to the current hotfix.
TMP="$(mktemp "$ROOT_DIR/install/.install-1.0.11-${TARGET_BUILD}.XXXXXX")"
sed "s/20260819\\.5/${TARGET_BUILD}/g" "$LEGACY" >"$TMP"
chmod 0755 "$TMP"
bash "$TMP" "$@"

# Auth daemon resilience hotfix. The web service must not enter a login-capable
# state without the isolated auth daemon, and the daemon must recreate its
# runtime directory/socket after process or /run lifecycle events.
install -m 0755 "$ROOT_DIR/system/control-center-authd" /usr/local/sbin/control-center-authd
install -m 0755 "$ROOT_DIR/system/control-center-auth-ready" /usr/local/sbin/control-center-auth-ready
install -d -m 0755 /etc/systemd/system/control-center-authd.service.d /etc/systemd/system/control-center.service.d
cat >/etc/systemd/system/control-center-authd.service.d/20-resilience.conf <<'UNIT'
[Service]
Group=control-center
Restart=always
RestartSec=1
RuntimeDirectory=control-center-auth
RuntimeDirectoryMode=0750
UNIT
cat >/etc/systemd/system/control-center.service.d/20-authd.conf <<'UNIT'
[Unit]
Requires=control-center-authd.service
After=control-center-authd.service
[Service]
ExecStartPre=/usr/local/sbin/control-center-auth-ready
UNIT

# Assert the immutable build identity after the complete privileged lifecycle.
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

systemctl daemon-reload
systemctl enable control-center-authd.service >/dev/null

# Prove dependency recovery rather than merely checking the happy path created
# by the legacy installer: remove both services and the socket, then start only
# the web service. Requires= must pull authd back in and ExecStartPre must wait
# for a usable socket.
systemctl stop control-center.service 2>/dev/null || true
systemctl stop control-center-authd.service 2>/dev/null || true
rm -f /run/control-center-auth/auth.sock
systemctl start control-center.service
systemctl is-active --quiet control-center-authd.service
/usr/local/sbin/control-center-auth-ready

# Verify the socket is actually usable by the unprivileged web identity. An
# intentionally invalid principal must produce a protocol response, not ENOENT.
runuser -u control-center -- python3 - <<'PY'
import json, socket
p='/run/control-center-auth/auth.sock'
s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
s.settimeout(5)
s.connect(p)
s.sendall(b'{"mode":"local","username":"__cc_probe__","password":"invalid"}\n')
raw=b''
while b'\n' not in raw and len(raw)<8192:
    part=s.recv(2048)
    if not part: break
    raw+=part
s.close()
reply=json.loads(raw.split(b'\n',1)[0].decode())
if reply.get('ok') is not False:
    raise SystemExit(f'unexpected auth probe response: {reply!r}')
PY

# Also prove self-healing when the socket path itself disappears while authd is
# still alive. The daemon polls for this condition and rebinds it.
rm -f /run/control-center-auth/auth.sock
/usr/local/sbin/control-center-auth-ready

PORT="$(sed -n 's/^CONTROL_CENTER_PORT=//p' /etc/control-center/web.env 2>/dev/null | head -1)"; PORT="${PORT:-8080}"
SSL="$(sed -n 's/^CONTROL_CENTER_SSL=//p' /etc/control-center/web.env 2>/dev/null | head -1)"; SSL="${SSL:-0}"
SCHEME=http; CURL=(-fsS --max-time 2)
if [[ "$SSL" == 1 || "$SSL" == true ]]; then SCHEME=https; CURL=(-kfsS --max-time 2); fi
health_ok=0
for _ in $(seq 1 30); do
  health="$(curl "${CURL[@]}" "$SCHEME://127.0.0.1:$PORT/api/health" 2>/dev/null || true)"
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

echo "Control Center 1.0.11 build $TARGET_BUILD installed; auth daemon resilience verified."
