#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

PRODUCT_REPO="https://github.com/ControlCenterSoft/srv-deployment.git"
PRODUCT_REF="f37f5162feb27e096b3089ea933f8b8e3a89acbb"
PRODUCT_VERSION="1.0.0-alpha.3"
DIAG_SSH="git@github.com:ControlCenterSoft/control-center-server-diagnostics..git"
DIAG_HTTPS="https://github.com/ControlCenterSoft/control-center-server-diagnostics..git"
BASE_URL="http://127.0.0.1:8876"
WORK_ROOT="/opt/control-center-test-host"
SRC_DIR="$WORK_ROOT/source"
REPORT_DIR="$WORK_ROOT/report"
FULL_LOG="$REPORT_DIR/full-install.log"
REPORT="$REPORT_DIR/report.txt"
DIAG_BUNDLE="$REPORT_DIR/control-center-diagnostics.tar.gz"
FINAL_CREDS="/root/control-center-admin-credentials.txt"
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
HOST="$(hostname -s 2>/dev/null || hostname)"
HOST_SAFE="$(printf '%s' "$HOST" | tr -cs 'A-Za-z0-9._-' '-')"
REPORT_BRANCH="reports/${HOST_SAFE}/${TS}"
STATUS="FAILED"
STEP="preflight"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo bash ..." >&2
  exit 1
fi

mkdir -p "$REPORT_DIR"
chmod 0700 "$WORK_ROOT" "$REPORT_DIR"
: > "$FULL_LOG"
exec > >(tee -a "$FULL_LOG") 2>&1

say() { printf '\n=== %s ===\n' "$*"; }
record() { printf '%s\n' "$*" >> "$REPORT"; }

report_push() {
  local remote="" tmp=""
  say "Report delivery"
  GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8' \
    git ls-remote "$DIAG_SSH" >/dev/null 2>&1 && remote="$DIAG_SSH" || true
  if [[ -z "$remote" ]]; then
    GIT_TERMINAL_PROMPT=0 git ls-remote "$DIAG_HTTPS" >/dev/null 2>&1 && remote="$DIAG_HTTPS" || true
  fi
  if [[ -z "$remote" ]]; then
    echo "No non-interactive GitHub credential is available for the private diagnostics repository."
    echo "Report kept locally: $REPORT"
    [[ -f "$DIAG_BUNDLE" ]] && echo "Diagnostics kept locally: $DIAG_BUNDLE"
    return 0
  fi

  tmp="$(mktemp -d /tmp/control-center-report-push.XXXXXX)"
  if ! GIT_TERMINAL_PROMPT=0 git clone -q "$remote" "$tmp/repo"; then
    echo "Diagnostics repository clone failed; report kept locally: $REPORT"
    rm -rf "$tmp"
    return 0
  fi
  cd "$tmp/repo"
  git checkout -q -b "$REPORT_BRANCH"
  mkdir -p "reports/$HOST_SAFE/$TS"
  cp "$REPORT" "reports/$HOST_SAFE/$TS/report.txt"
  if [[ -f "$DIAG_BUNDLE" ]]; then
    cp "$DIAG_BUNDLE" "reports/$HOST_SAFE/$TS/control-center-diagnostics.tar.gz"
  fi
  git add -- "reports/$HOST_SAFE/$TS/report.txt"
  [[ ! -f "$DIAG_BUNDLE" ]] || git add -- "reports/$HOST_SAFE/$TS/control-center-diagnostics.tar.gz"
  git -c user.name='Control Center Test Host' -c user.email='control-center-test-host@localhost' \
    commit -q -m "Test host report: $HOST_SAFE $TS"
  if GIT_TERMINAL_PROMPT=0 git push -q origin "$REPORT_BRANCH"; then
    echo "REPORT_SENT=YES"
    echo "REPORT_BRANCH=$REPORT_BRANCH"
  else
    echo "Report push failed; report kept locally: $REPORT"
  fi
  cd /
  rm -rf "$tmp"
}

finalize() {
  local rc=$?
  trap - EXIT
  mkdir -p "$REPORT_DIR"
  {
    echo "CONTROL CENTER TEST HOST REPORT"
    echo "started_at=$STARTED_AT"
    echo "finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "host=$HOST"
    echo "status=$STATUS"
    echo "last_step=$STEP"
    echo "product_version=$PRODUCT_VERSION"
    echo "product_commit=$PRODUCT_REF"
    echo "architecture=$(uname -m 2>/dev/null || true)"
    echo "kernel=$(uname -sr 2>/dev/null || true)"
    if [[ -r /etc/os-release ]]; then
      . /etc/os-release
      echo "os=${PRETTY_NAME:-unknown}"
    fi
    echo "service_active=$(systemctl is-active control-center.service 2>/dev/null || true)"
    echo "service_enabled=$(systemctl is-enabled control-center.service 2>/dev/null || true)"
    echo "admin_credentials_file=$FINAL_CREDS"
    echo
    echo "--- VERSION ---"
    curl -fsS "$BASE_URL/api/v1/version" 2>/dev/null || true
    echo
    echo "--- READINESS ---"
    curl -fsS "$BASE_URL/api/v1/readiness" 2>/dev/null || true
    echo
    echo "--- SYSTEMD STATUS ---"
    systemctl status control-center.service --no-pager -l 2>&1 | tail -n 80 || true
    echo
    echo "--- PRODUCT FILES ---"
    find /etc/control-center /var/lib/control-center /var/log/control-center -maxdepth 1 -printf '%M %u:%g %p\n' 2>/dev/null | sort || true
    echo
    echo "--- JOURNAL TAIL ---"
    journalctl -u control-center.service --no-pager -n 160 2>&1 || true
    echo
    echo "NOTE: bootstrap credentials, password hashes, cookies, CSRF tokens and request bodies are intentionally excluded."
  } > "$REPORT"
  chmod 0600 "$REPORT"
  report_push || true
  echo
  echo "FINAL_STATUS=$STATUS"
  echo "LOCAL_REPORT=$REPORT"
  [[ -f "$DIAG_BUNDLE" ]] && echo "LOCAL_DIAGNOSTICS=$DIAG_BUNDLE"
  [[ -f "$FINAL_CREDS" ]] && echo "ADMIN_CREDENTIALS=$FINAL_CREDS"
  exit "$rc"
}
trap finalize EXIT

say "Preflight"
STEP="install-dependencies"
export DEBIAN_FRONTEND=noninteractive
export GIT_SSH_COMMAND='ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8'
apt-get update -qq
apt-get install -y -qq git curl ca-certificates golang-go python3 tar gzip openssh-client >/dev/null
for c in git curl go python3 tar sha256sum systemctl; do command -v "$c" >/dev/null || { echo "Missing command: $c"; exit 1; }; done
[[ -d /run/systemd/system ]] || { echo "systemd is not running"; exit 1; }
go version

say "Fetch exact alpha.3 commit"
STEP="fetch-source"
rm -rf "$SRC_DIR"
mkdir -p "$SRC_DIR"
git -C "$WORK_ROOT" init -q source
git -C "$SRC_DIR" remote add origin "$PRODUCT_REPO"
git -C "$SRC_DIR" fetch -q --depth=1 origin "$PRODUCT_REF"
git -C "$SRC_DIR" checkout -q --detach FETCH_HEAD
actual="$(git -C "$SRC_DIR" rev-parse HEAD)"
[[ "$actual" == "$PRODUCT_REF" ]] || { echo "Commit mismatch: $actual"; exit 1; }
echo "SOURCE_COMMIT=$actual"

say "Static validation and build"
STEP="build"
cd "$SRC_DIR"
test -z "$(gofmt -l .)"
go vet ./...
go test ./...
bash -n install/install.sh install/uninstall.sh scripts/build.sh scripts/auth-acceptance.sh scripts/operations-acceptance.sh
VERSION="$PRODUCT_VERSION+testhost" COMMIT="$PRODUCT_REF" ./scripts/build.sh
sha256sum -c dist/SHA256SUMS

say "Install"
STEP="install"
./install/install.sh
systemctl is-active --quiet control-center.service
curl -fsS "$BASE_URL/api/v1/health"; echo
curl -fsS "$BASE_URL/api/v1/readiness"; echo
curl -fsS "$BASE_URL/api/v1/version"; echo

say "Restart acceptance"
STEP="restart"
systemctl restart control-center.service
systemctl is-active --quiet control-center.service
curl -fsS "$BASE_URL/api/v1/readiness" >/dev/null

say "Auth/RBAC acceptance"
STEP="auth-rbac"
./scripts/auth-acceptance.sh

say "Operations/diagnostics acceptance"
STEP="operations-diagnostics"
./scripts/operations-acceptance.sh

say "Repair/reinstall acceptance"
STEP="repair-reinstall"
./install/install.sh --repair
./install/install.sh --reinstall
systemctl is-active --quiet control-center.service
curl -fsS "$BASE_URL/api/v1/readiness" >/dev/null

say "Preserve-state uninstall/reinstall acceptance"
STEP="preserve-reinstall"
./install/uninstall.sh
[[ -f /etc/control-center/control-center.env ]]
[[ -d /var/lib/control-center ]]
./install/install.sh
systemctl is-active --quiet control-center.service
curl -fsS "$BASE_URL/api/v1/readiness" >/dev/null

say "Final security cleanup and diagnostics"
STEP="final-security-cleanup"
SEC_WORK="$(mktemp -d /tmp/control-center-finalize.XXXXXX)"
chmod 0700 "$SEC_WORK"
ADMIN_TEST_PASSWORD='alpha2-acceptance-password-123'
python3 - "$ADMIN_TEST_PASSWORD" > "$SEC_WORK/login.json" <<'PY'
import json,sys
print(json.dumps({'username':'admin','password':sys.argv[1]}))
PY
http="$(curl -sS -D "$SEC_WORK/headers" -o "$SEC_WORK/login-body" -w '%{http_code}' \
  -H 'Content-Type: application/json' -H "Origin: $BASE_URL" --data-binary "@$SEC_WORK/login.json" "$BASE_URL/api/v1/auth/login")"
[[ "$http" == 200 ]] || { echo "Final admin login failed: HTTP $http"; exit 1; }
TOKEN="$(sed -n 's/^Set-Cookie: cc_session=\([^;]*\).*/\1/p' "$SEC_WORK/headers" | tr -d '\r' | head -1)"
CSRF="$(python3 - "$SEC_WORK/login-body" <<'PY'
import json,sys
print(json.load(open(sys.argv[1]))['csrf_token'])
PY
)"
[[ -n "$TOKEN" && -n "$CSRF" ]] || { echo "Missing final session material"; exit 1; }

curl -fsS -H "Cookie: cc_session=$TOKEN" "$BASE_URL/api/v1/diagnostics/export" -o "$DIAG_BUNDLE"
tar -tzf "$DIAG_BUNDLE" | sort
: > "$SEC_WORK/diagnostics-expanded.txt"
while IFS= read -r entry; do
  tar -xOzf "$DIAG_BUNDLE" "$entry" >> "$SEC_WORK/diagnostics-expanded.txt"
done < <(tar -tzf "$DIAG_BUNDLE")
for forbidden in 'pbkdf2-sha256' 'bootstrap-admin.secret' 'cc_session'; do
  if grep -q "$forbidden" "$SEC_WORK/diagnostics-expanded.txt"; then
    echo "Diagnostics leak check failed: $forbidden"; exit 1
  fi
done

printf '{"blocked":true}\n' > "$SEC_WORK/block-viewer.json"
code="$(curl -sS -o "$SEC_WORK/block-viewer-result" -w '%{http_code}' \
  -H 'Content-Type: application/json' -H "Origin: $BASE_URL" \
  -H "Cookie: cc_session=$TOKEN" -H "X-CSRF-Token: $CSRF" \
  --data-binary "@$SEC_WORK/block-viewer.json" "$BASE_URL/api/v1/rbac/users/viewer/blocked")"
[[ "$code" == 200 ]] || { echo "Could not block acceptance viewer: HTTP $code"; exit 1; }

NEW_PASSWORD="$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(32))
PY
)"
python3 - "$ADMIN_TEST_PASSWORD" "$NEW_PASSWORD" > "$SEC_WORK/change-password.json" <<'PY'
import json,sys
print(json.dumps({'current_password':sys.argv[1],'new_password':sys.argv[2]}))
PY
code="$(curl -sS -o "$SEC_WORK/change-password-result" -w '%{http_code}' \
  -H 'Content-Type: application/json' -H "Origin: $BASE_URL" \
  -H "Cookie: cc_session=$TOKEN" -H "X-CSRF-Token: $CSRF" \
  --data-binary "@$SEC_WORK/change-password.json" "$BASE_URL/api/v1/auth/password")"
[[ "$code" == 200 ]] || { echo "Final admin password rotation failed: HTTP $code"; exit 1; }
printf 'username=admin\npassword=%s\n' "$NEW_PASSWORD" > "$FINAL_CREDS"
chmod 0600 "$FINAL_CREDS"

systemctl restart control-center.service
for _ in {1..20}; do
  curl -fsS "$BASE_URL/api/v1/health" >/dev/null 2>&1 && break
  sleep 0.5
done
python3 - "$NEW_PASSWORD" > "$SEC_WORK/final-login.json" <<'PY'
import json,sys
print(json.dumps({'username':'admin','password':sys.argv[1]}))
PY
code="$(curl -sS -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -H "Origin: $BASE_URL" --data-binary "@$SEC_WORK/final-login.json" "$BASE_URL/api/v1/auth/login")"
[[ "$code" == 200 ]] || { echo "Final random-password login failed: HTTP $code"; exit 1; }
rm -rf "$SEC_WORK"

STEP="completed"
STATUS="PASSED"
say "Acceptance completed"
echo "Control Center $PRODUCT_VERSION is installed and healthy."
echo "Admin credentials: $FINAL_CREDS"
