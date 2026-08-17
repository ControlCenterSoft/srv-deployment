#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="0010-adguard-security"
RELEASE_VERSION="0.10.0"
BACKUP_DIR="/var/lib/srv-deployment/backups/${REMOTE_SHA}-${RELEASE_ID}"
fail() { printf 'ACCEPTANCE FAIL: %s\n' "$*" >&2; exit 1; }

systemctl is-active --quiet srv-control.service || fail "srv-control.service is not active"
systemctl is-active --quiet srv-control-system-agent.path || fail "system action path unit is not active"
systemctl is-active --quiet srv-control-adguard-monitor.timer || fail "AdGuard status timer is not active"
[[ -x /usr/local/libexec/srv-control-system-agent ]] || fail "system action agent missing"
[[ -x /usr/local/libexec/srv-control-adguard-monitor ]] || fail "AdGuard monitor missing"
systemctl start srv-control-adguard-monitor.service || true
[[ -s /var/lib/srv-control/adguard-vpn-status.json ]] || fail "AdGuard status snapshot missing"

before_pid="$(cat "$BACKUP_DIR/main-pid.before" 2>/dev/null || true)"
after_pid="$(systemctl show srv-control.service -p MainPID --value)"
[[ -n "$before_pid" && "$before_pid" == "$after_pid" ]] || fail "Uvicorn manager PID changed"

python3 - "$RELEASE_VERSION" "$REMOTE_SHA" <<'PY'
import http.cookiejar, json, pathlib, sys, urllib.request
version, sha = sys.argv[1], sys.argv[2]
base = "http://127.0.0.1:8876"
def get(path, opener=None):
    opener = opener or urllib.request
    with opener.open(base + path, timeout=8) as response: return json.load(response)

health = get("/api/v1/health"); release = health.get("data",{}).get("release",{})
assert health.get("ok") is True and release.get("version") == version and release.get("git_sha") == sha, health
admin = get("/api/v1/system/admin"); data = admin.get("data",{})
assert admin.get("ok") is True, admin
assert data.get("actions",{}).get("visible") is False, data
assert data.get("actions",{}).get("history") == [], data
adguard = next(item for item in data.get("services",[]) if item.get("id") == "adguard-vpn")
assert adguard.get("safety",{}).get("connect_mode") == "SOCKS", adguard
assert adguard.get("safety",{}).get("system_default_route_changed") is False, adguard

page = urllib.request.urlopen(base + "/ui/module/system", timeout=8).read().decode("utf-8","replace")
for marker in ('id="systemActionPanel"','id="managedServices"','id="rebootButton"','adguardvpn-cli login'): assert marker in page, marker

bootstrap = pathlib.Path("/var/lib/srv-control/admin-bootstrap.txt")
if bootstrap.exists():
    values = {}
    for line in bootstrap.read_text(encoding="utf-8").splitlines():
        if "=" in line:
            k,v=line.split("=",1); values[k.strip()]=v.strip()
    jar=http.cookiejar.CookieJar(); opener=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    req=urllib.request.Request(base+"/api/v1/auth/login", data=json.dumps({"username":values["username"],"password":values["password"]}).encode(), headers={"Content-Type":"application/json"}, method="POST")
    with opener.open(req,timeout=8) as response: login=json.load(response)
    assert login.get("ok") is True, login
    protected=get("/api/v1/system/admin",opener=opener).get("data",{})
    assert protected.get("actions",{}).get("visible") is True, protected
    assert isinstance(protected.get("actions",{}).get("history"),list), protected

print(json.dumps({"release":release,"protected_history":True,"adguard_monitor":True,"safe_mode":"SOCKS","graceful_manager_pid":True},ensure_ascii=False))
PY
printf 'ACCEPTANCE PASS: release=%s sha=%s\n' "$RELEASE_VERSION" "$REMOTE_SHA"
