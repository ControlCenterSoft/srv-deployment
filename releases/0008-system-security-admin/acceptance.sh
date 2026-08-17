#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="0008-system-security-admin"
RELEASE_VERSION="0.8.0"
BACKUP_DIR="/var/lib/srv-deployment/backups/${REMOTE_SHA}-${RELEASE_ID}"

fail() {
    printf 'ACCEPTANCE FAIL: %s\n' "$*" >&2
    exit 1
}

systemctl is-active --quiet srv-control.service \
    || fail "srv-control.service is not active"
systemctl is-active --quiet srv-control-system-agent.path \
    || fail "privileged system action path unit is not active"

[[ -s /var/lib/srv-control/auth.json ]] || fail "auth state missing"
[[ -s /var/lib/srv-control/session.key ]] || fail "session signing key missing"
[[ -x /usr/local/libexec/srv-control-system-agent ]] || fail "system action agent missing"
[[ -x /usr/local/libexec/srv-control-os-update ]] || fail "OS update worker missing"

before_pid="$(cat "$BACKUP_DIR/main-pid.before" 2>/dev/null || true)"
after_pid="$(systemctl show srv-control.service -p MainPID --value)"
[[ -n "$before_pid" && "$before_pid" == "$after_pid" ]] \
    || fail "Uvicorn manager PID changed; graceful reload invariant failed"

python3 - "$RELEASE_VERSION" "$REMOTE_SHA" <<'PY'
import http.cookiejar
import json
import pathlib
import sys
import urllib.error
import urllib.request

version = sys.argv[1]
sha = sys.argv[2]
base = "http://127.0.0.1:8876"

def get(path):
    with urllib.request.urlopen(base + path, timeout=8) as response:
        return json.load(response)

health = get("/api/v1/health")
release = health.get("data", {}).get("release", {})
assert health.get("ok") is True, health
assert release.get("version") == version, release
assert release.get("git_sha") == sha, release

admin = get("/api/v1/system/admin")
assert admin.get("ok") is True, admin
data = admin.get("data", {})
assert isinstance(data.get("services"), list), data
assert any(item.get("id") == "adguard-vpn" for item in data["services"]), data
assert "automatic_updates" in data, data
assert "manual_update" in data, data

auth = get("/api/v1/auth/status")
assert auth.get("data", {}).get("authenticated") is False, auth

page = urllib.request.urlopen(base + "/ui/module/system", timeout=8).read().decode(
    "utf-8", "replace"
)
for marker in (
    'id="rebootButton"',
    'id="manualUpdateButton"',
    'id="managedServices"',
    'id="adminLoginForm"',
):
    assert marker in page, marker

bootstrap = pathlib.Path("/var/lib/srv-control/admin-bootstrap.txt")
if bootstrap.exists():
    values = {}
    for line in bootstrap.read_text(encoding="utf-8").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()

    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(jar)
    )

    login_request = urllib.request.Request(
        base + "/api/v1/auth/login",
        data=json.dumps(
            {
                "username": values["username"],
                "password": values["password"],
            }
        ).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with opener.open(login_request, timeout=8) as response:
        login = json.load(response)

    assert login.get("ok") is True, login
    assert login.get("data", {}).get("must_change") is True, login

    blocked = urllib.request.Request(
        base + "/api/v1/system/actions/reboot",
        data=b'{"confirm":"REBOOT"}',
        headers={
            "Content-Type": "application/json",
            "X-CSRF-Token": login["data"]["csrf_token"],
        },
        method="POST",
    )
    try:
        opener.open(blocked, timeout=8)
        raise AssertionError("bootstrap session unexpectedly allowed reboot")
    except urllib.error.HTTPError as exc:
        assert exc.code == 403, exc.code

print(
    json.dumps(
        {
            "release": release,
            "system_admin": True,
            "auth": True,
            "graceful_manager_pid": True,
        },
        ensure_ascii=False,
    )
)
PY

printf 'ACCEPTANCE PASS: release=%s sha=%s\n' "$RELEASE_VERSION" "$REMOTE_SHA"
