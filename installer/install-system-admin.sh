#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
STATE_DIR="/var/lib/srv-control"
APP_USER="srv-control"
APP_GROUP="srv-control"

fail() {
    printf 'SYSTEM ADMIN INSTALL FAIL: %s\n' "$*" >&2
    exit 1
}

[[ "$(id -u)" -eq 0 ]] || fail "must run as root"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"

release_path="$(python3 - "$REPO_ROOT/deployment.json" <<'PY'
import json
import pathlib
import sys

config=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
value=config.get("release_path")
if not isinstance(value,str) or not value:
    raise SystemExit("release_path missing")
print(value)
PY
)"
SYSTEM_DIR="$REPO_ROOT/$release_path/system"

[[ -x "$SYSTEM_DIR/srv-control-system-agent" ]] || fail "system agent payload missing"
[[ -x "$SYSTEM_DIR/srv-control-os-update" ]] || fail "OS update worker payload missing"
[[ -x "$SYSTEM_DIR/srv-control-adguard-monitor" ]] || fail "AdGuard monitor payload missing"

install -d -m 0750 -o "$APP_USER" -g "$APP_GROUP" \
    "$STATE_DIR" \
    "$STATE_DIR/system-actions" \
    "$STATE_DIR/system-results"
install -d -m 0755 /usr/local/libexec

for executable in \
    srv-control-system-agent \
    srv-control-os-update \
    srv-control-adguard-monitor
do
    install -m 0755 -o root -g root \
        "$SYSTEM_DIR/$executable" \
        "/usr/local/libexec/$executable"
done

for unit in \
    srv-control-system-agent.service \
    srv-control-system-agent.path \
    srv-control-os-update.service \
    srv-control-adguard-monitor.service \
    srv-control-adguard-monitor.timer
do
    install -m 0644 -o root -g root \
        "$SYSTEM_DIR/$unit" \
        "/etc/systemd/system/$unit"
done

if [[ ! -s "$STATE_DIR/session.key" ]]; then
    python3 - "$STATE_DIR/session.key" <<'PY'
import os
import pathlib
import sys
path=pathlib.Path(sys.argv[1])
path.write_text(os.urandom(32).hex()+"\n",encoding="ascii")
PY
    chown "$APP_USER:$APP_GROUP" "$STATE_DIR/session.key"
    chmod 0600 "$STATE_DIR/session.key"
fi

if [[ ! -s "$STATE_DIR/auth.json" ]]; then
    python3 - "$STATE_DIR/auth.json" "$STATE_DIR/admin-bootstrap.txt" <<'PY'
import hashlib
import json
import os
import pathlib
import secrets
import string
import sys

auth_path=pathlib.Path(sys.argv[1])
bootstrap_path=pathlib.Path(sys.argv[2])
alphabet=string.ascii_letters+string.digits+"-_"
password="".join(secrets.choice(alphabet) for _ in range(24))
salt=os.urandom(16)
iterations=310000
password_hash=hashlib.pbkdf2_hmac(
    "sha256",password.encode("utf-8"),salt,iterations
).hex()
auth={
    "schema_version":2,
    "username":"admin",
    "salt":salt.hex(),
    "password_hash":password_hash,
    "iterations":iterations,
    "must_change":True,
    "session_generation":1,
}
auth_path.write_text(json.dumps(auth,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
bootstrap_path.write_text(
    "SRV Control Center initial administrator\n"
    "username=admin\n"
    f"password={password}\n"
    "The web UI requires changing this password before privileged actions.\n",
    encoding="utf-8",
)
PY
    chown "$APP_USER:$APP_GROUP" "$STATE_DIR/auth.json"
    chmod 0640 "$STATE_DIR/auth.json"
    chown root:root "$STATE_DIR/admin-bootstrap.txt"
    chmod 0600 "$STATE_DIR/admin-bootstrap.txt"
fi

touch "$STATE_DIR/login-guard.json"
chown "$APP_USER:$APP_GROUP" "$STATE_DIR/login-guard.json"
chmod 0640 "$STATE_DIR/login-guard.json"

systemctl daemon-reload
systemctl enable --now srv-control-system-agent.path
systemctl enable --now srv-control-adguard-monitor.timer
systemctl start srv-control-adguard-monitor.service || true

printf 'SYSTEM ADMIN INSTALL PASS: source=%s\n' "$release_path/system"
