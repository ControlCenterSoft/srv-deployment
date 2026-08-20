#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

PRODUCT_REF="29c0d19418113ee05835e8fc67e4a9e799dfc7f3"
PRODUCT_VERSION="1.0.0-alpha.3"
PRODUCT_REPO="https://github.com/ControlCenterSoft/srv-deployment.git"
DIAG_SSH="git@github.com:ControlCenterSoft/control-center-server-diagnostics..git"
DIAG_HTTPS="https://github.com/ControlCenterSoft/control-center-server-diagnostics..git"
BASE_URL="http://127.0.0.1:8876"
WORK_ROOT="/opt/control-center-test-host"
SRC_DIR="$WORK_ROOT/source"
REPORT_DIR="$WORK_ROOT/report"
REPORT="$REPORT_DIR/report-resume.txt"
FULL_LOG="$REPORT_DIR/resume.log"
DIAG_BUNDLE="$REPORT_DIR/control-center-diagnostics.tar.gz"
FINAL_CREDS="/root/control-center-admin-credentials.txt"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
HOST="$(hostname -s 2>/dev/null || hostname)"
HOST_SAFE="$(printf '%s' "$HOST" | tr -cs 'A-Za-z0-9._-' '-')"
REPORT_BRANCH="reports/${HOST_SAFE}/${TS}-alpha3-rerun"
STATUS="FAILED"
STEP="preflight"

[[ $EUID -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
mkdir -p "$REPORT_DIR"; chmod 0700 "$WORK_ROOT" "$REPORT_DIR"
: > "$FULL_LOG"
exec > >(tee -a "$FULL_LOG") 2>&1

wait_ready() {
  local i
  for i in {1..40}; do
    if curl -fsS --max-time 2 "$BASE_URL/api/v1/readiness" >/dev/null 2>&1; then return 0; fi
    sleep 0.25
  done
  return 1
}

push_report() {
  local remote="" tmp
  GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8' git ls-remote "$DIAG_SSH" >/dev/null 2>&1 && remote="$DIAG_SSH" || true
  [[ -n "$remote" ]] || { GIT_TERMINAL_PROMPT=0 git ls-remote "$DIAG_HTTPS" >/dev/null 2>&1 && remote="$DIAG_HTTPS" || true; }
  if [[ -z "$remote" ]]; then echo "REPORT_SENT=NO"; return 0; fi
  tmp="$(mktemp -d /tmp/cc-report.XXXXXX)"
  GIT_TERMINAL_PROMPT=0 git clone -q "$remote" "$tmp/repo" || { rm -rf "$tmp"; echo "REPORT_SENT=NO"; return 0; }
  cd "$tmp/repo"
  git checkout -q -b "$REPORT_BRANCH"
  mkdir -p "reports/$HOST_SAFE/$TS"
  cp "$REPORT" "reports/$HOST_SAFE/$TS/report.txt"
  [[ ! -f "$DIAG_BUNDLE" ]] || cp "$DIAG_BUNDLE" "reports/$HOST_SAFE/$TS/control-center-diagnostics.tar.gz"
  git add "reports/$HOST_SAFE/$TS"
  git -c user.name='Control Center Test Host' -c user.email='control-center-test-host@localhost' commit -q -m "Alpha3 rerun report: $HOST_SAFE $TS"
  if GIT_TERMINAL_PROMPT=0 git push -q origin "$REPORT_BRANCH"; then
    echo "REPORT_SENT=YES"
    echo "REPORT_BRANCH=$REPORT_BRANCH"
  else
    echo "REPORT_SENT=NO"
  fi
  cd /; rm -rf "$tmp"
}

finalize() {
  local rc=$?
  trap - EXIT
  {
    echo "CONTROL CENTER ALPHA3 REAL-HOST ACCEPTANCE"
    echo "finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "host=$HOST"
    echo "status=$STATUS"
    echo "last_step=$STEP"
    echo "product_version=$PRODUCT_VERSION"
    echo "product_commit=$PRODUCT_REF"
    echo "service_active=$(systemctl is-active control-center.service 2>/dev/null || true)"
    echo "service_enabled=$(systemctl is-enabled control-center.service 2>/dev/null || true)"
    echo "config_mode=$(stat -c %a /etc/control-center 2>/dev/null || true)"
    echo "state_mode=$(stat -c %a /var/lib/control-center 2>/dev/null || true)"
    echo "log_mode=$(stat -c %a /var/log/control-center 2>/dev/null || true)"
    echo
    echo "--- VERSION ---"; curl -fsS "$BASE_URL/api/v1/version" 2>/dev/null || true; echo
    echo "--- READINESS ---"; curl -fsS "$BASE_URL/api/v1/readiness" 2>/dev/null || true; echo
    echo "--- SYSTEMD STATUS ---"; systemctl status control-center.service --no-pager -l 2>&1 | tail -n 80 || true
    echo "--- JOURNAL TAIL ---"; journalctl -u control-center.service --no-pager -n 200 2>&1 || true
    echo "NOTE: credentials, password hashes, cookies, CSRF tokens and request bodies are excluded."
  } > "$REPORT"
  chmod 0600 "$REPORT"
  push_report || true
  echo "FINAL_STATUS=$STATUS"
  echo "LOCAL_REPORT=$REPORT"
  [[ -f "$DIAG_BUNDLE" ]] && echo "LOCAL_DIAGNOSTICS=$DIAG_BUNDLE"
  [[ -f "$FINAL_CREDS" ]] && echo "ADMIN_CREDENTIALS=$FINAL_CREDS"
  exit "$rc"
}
trap finalize EXIT

export DEBIAN_FRONTEND=noninteractive
export GIT_SSH_COMMAND='ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8'

STEP="fetch-fixed-alpha3"
echo "=== Fetch fixed alpha.3 ==="
if [[ ! -d "$SRC_DIR/.git" ]]; then
  rm -rf "$SRC_DIR"; mkdir -p "$SRC_DIR"; git -C "$WORK_ROOT" init -q source; git -C "$SRC_DIR" remote add origin "$PRODUCT_REPO"
fi
git -C "$SRC_DIR" fetch -q --depth=1 origin "$PRODUCT_REF"
git -C "$SRC_DIR" checkout -q --detach FETCH_HEAD
[[ "$(git -C "$SRC_DIR" rev-parse HEAD)" == "$PRODUCT_REF" ]]

STEP="validate-build"
echo "=== Validate and build ==="
cd "$SRC_DIR"
test -z "$(gofmt -l .)"
go vet ./...
go test ./...
bash -n install/install.sh install/uninstall.sh scripts/build.sh scripts/auth-acceptance.sh scripts/operations-acceptance.sh
VERSION="$PRODUCT_VERSION+testhost" COMMIT="$PRODUCT_REF" ./scripts/build.sh
sha256sum -c dist/SHA256SUMS

STEP="install-fix"
echo "=== Install fixed candidate ==="
./install/install.sh --reinstall
systemctl is-active --quiet control-center.service
wait_ready
[[ "$(stat -c %a /etc/control-center)" == 750 ]]
[[ "$(stat -c %a /var/lib/control-center)" == 750 ]]
[[ "$(stat -c %a /var/log/control-center)" == 750 ]]

STEP="restart"
echo "=== Restart acceptance ==="
systemctl restart control-center.service
systemctl is-active --quiet control-center.service
wait_ready
curl -fsS "$BASE_URL/api/v1/readiness"; echo

STEP="auth-rbac"
echo "=== Auth/RBAC acceptance ==="
if [[ -f /var/lib/control-center/bootstrap-admin.secret ]]; then
  ./scripts/auth-acceptance.sh
else
  echo "Bootstrap secret already consumed; refusing to guess credentials."
  echo "If this is a rerun after completed Auth acceptance, use /root/control-center-admin-credentials.txt."
  exit 1
fi

STEP="operations-diagnostics"
echo "=== Operations/diagnostics acceptance ==="
./scripts/operations-acceptance.sh

STEP="repair-reinstall"
echo "=== Repair/reinstall acceptance ==="
./install/install.sh --repair
./install/install.sh --reinstall
wait_ready

STEP="preserve-state"
echo "=== Preserve-state uninstall/reinstall ==="
./install/uninstall.sh
[[ -f /etc/control-center/control-center.env ]]
[[ -d /var/lib/control-center ]]
./install/install.sh
wait_ready

STEP="security-cleanup"
echo "=== Security cleanup and diagnostic export ==="
SEC_WORK="$(mktemp -d /tmp/cc-final.XXXXXX)"; chmod 0700 "$SEC_WORK"
TEST_PASSWORD='alpha2-acceptance-password-123'
python3 - "$TEST_PASSWORD" > "$SEC_WORK/login.json" <<'PY'
import json,sys
print(json.dumps({'username':'admin','password':sys.argv[1]}))
PY
code="$(curl -sS -D "$SEC_WORK/h" -o "$SEC_WORK/b" -w '%{http_code}' -H 'Content-Type: application/json' -H "Origin: $BASE_URL" --data-binary "@$SEC_WORK/login.json" "$BASE_URL/api/v1/auth/login")"
[[ "$code" == 200 ]]
TOKEN="$(sed -n 's/^Set-Cookie: cc_session=\([^;]*\).*/\1/p' "$SEC_WORK/h" | tr -d '\r' | head -1)"
CSRF="$(python3 - "$SEC_WORK/b" <<'PY'
import json,sys
print(json.load(open(sys.argv[1]))['csrf_token'])
PY
)"

curl -fsS -H "Cookie: cc_session=$TOKEN" "$BASE_URL/api/v1/diagnostics/export" -o "$DIAG_BUNDLE"
: > "$SEC_WORK/expanded"
while IFS= read -r entry; do tar -xOzf "$DIAG_BUNDLE" "$entry" >> "$SEC_WORK/expanded"; done < <(tar -tzf "$DIAG_BUNDLE")
for forbidden in 'pbkdf2-sha256' 'bootstrap-admin.secret' 'cc_session'; do ! grep -q "$forbidden" "$SEC_WORK/expanded"; done

printf '{"blocked":true}\n' > "$SEC_WORK/block.json"
code="$(curl -sS -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -H "Origin: $BASE_URL" -H "Cookie: cc_session=$TOKEN" -H "X-CSRF-Token: $CSRF" --data-binary "@$SEC_WORK/block.json" "$BASE_URL/api/v1/rbac/users/viewer/blocked")"
[[ "$code" == 200 ]]

NEW_PASSWORD="$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(32))
PY
)"
python3 - "$TEST_PASSWORD" "$NEW_PASSWORD" > "$SEC_WORK/change.json" <<'PY'
import json,sys
print(json.dumps({'current_password':sys.argv[1],'new_password':sys.argv[2]}))
PY
code="$(curl -sS -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -H "Origin: $BASE_URL" -H "Cookie: cc_session=$TOKEN" -H "X-CSRF-Token: $CSRF" --data-binary "@$SEC_WORK/change.json" "$BASE_URL/api/v1/auth/password")"
[[ "$code" == 200 ]]
printf 'username=admin\npassword=%s\n' "$NEW_PASSWORD" > "$FINAL_CREDS"; chmod 0600 "$FINAL_CREDS"
rm -rf "$SEC_WORK"

STEP="final-restart"
systemctl restart control-center.service
wait_ready

STEP="completed"
STATUS="PASSED"
echo "=== ALPHA3 REAL-HOST ACCEPTANCE PASSED ==="
