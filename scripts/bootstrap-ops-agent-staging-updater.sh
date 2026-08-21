#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

STAGING_USER="${CONTROL_CENTER_STAGING_USER:-control-center-staging}"
UPDATER="/usr/local/sbin/control-center-ops-agent-staging-update"
SUDOERS="/etc/sudoers.d/control-center-ops-agent-staging"
PUBLIC_KEY="/etc/control-center/staging-update-public.pem"

fail() { printf 'OPS_AGENT_STAGING_BOOTSTRAP_FAILED: %s\n' "$*" >&2; return 1; }
[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "run as root"
[[ "$STAGING_USER" =~ ^[a-z_][a-z0-9_-]{0,30}$ ]] || fail "invalid staging user"
id "$STAGING_USER" >/dev/null 2>&1 || fail "existing staging user missing"
[[ -s "$PUBLIC_KEY" ]] || fail "existing staging public key missing"
for bin in bash cp id install mktemp openssl python3 rm runuser stat sudo visudo; do
  command -v "$bin" >/dev/null 2>&1 || fail "missing required command: $bin"
done

work="$(mktemp -d /tmp/control-center-ops-agent-staging-bootstrap.XXXXXX)"
backup_updater="$work/updater.previous"
backup_sudoers="$work/sudoers.previous"
had_updater=0
had_sudoers=0
[[ -f "$UPDATER" && ! -L "$UPDATER" ]] && { cp -a -- "$UPDATER" "$backup_updater"; had_updater=1; }
[[ -f "$SUDOERS" && ! -L "$SUDOERS" ]] && { cp -a -- "$SUDOERS" "$backup_sudoers"; had_sudoers=1; }
rollback() {
  local rc=$?
  if (( had_updater )); then cp -a -- "$backup_updater" "$UPDATER"; else rm -f -- "$UPDATER"; fi
  if (( had_sudoers )); then cp -a -- "$backup_sudoers" "$SUDOERS"; else rm -f -- "$SUDOERS"; fi
  rm -rf -- "$work"
  exit "$rc"
}
trap rollback ERR

cat > "$work/control-center-ops-agent-staging-update" <<'WRAPPER'
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

STAGING_USER="control-center-staging"
PUBLIC_KEY="/etc/control-center/staging-update-public.pem"
AGENT_USER="ccdiag"
AGENT_FILE="/opt/control-center-diagnostics-agent/ccops_agent_v3.py"
STATE_DIR="/var/lib/control-center-ops-agent/state"
BACKUP_ROOT="/var/lib/control-center-ops-agent/backups"
STAGING_ROOT="/var/lib/control-center-ops-agent/staging"
CONFIG_FILE="/etc/control-center-diagnostics-agent/agent.conf"
TOKEN_FILE="/etc/control-center-diagnostics-agent/github-token"
BROKER_SERVICE="control-center-ops-broker.service"
AGENT_SERVICE="control-center-ops-agent.service"
AGENT_TIMER="control-center-ops-agent.timer"
BROKER_SOCKET="/run/control-center-ops/broker.sock"
MAX_PACKAGE_BYTES=524288
MAX_AGENT_BYTES=131072
PACKAGE=""
MODE="apply"

fail() { printf 'OPS_AGENT_STAGING_UPDATE_FAILED: %s\n' "$*" >&2; return 1; }
if [[ ${1:-} == --self-test && $# -eq 1 ]]; then MODE="self-test"; shift
elif [[ ${1:-} == --package && $# -eq 2 ]]; then PACKAGE="$2"; shift 2
else fail "usage: control-center-ops-agent-staging-update --self-test | --package PATH"
fi
[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "updater must run as root"
for bin in awk curl date dirname grep id install mktemp mv openssl python3 realpath rm runuser sha256sum sleep stat systemctl; do command -v "$bin" >/dev/null 2>&1 || fail "missing required command: $bin"; done
id "$STAGING_USER" >/dev/null 2>&1 || fail "staging user missing"
id "$AGENT_USER" >/dev/null 2>&1 || fail "agent user missing"
[[ -s "$PUBLIC_KEY" && ! -L "$PUBLIC_KEY" ]] || fail "staging public key unavailable"
[[ -f "$AGENT_FILE" && ! -L "$AGENT_FILE" ]] || fail "installed agent unavailable"
[[ -d "$STATE_DIR" && ! -L "$STATE_DIR" ]] || fail "agent state directory unavailable"
[[ -f "$CONFIG_FILE" && ! -L "$CONFIG_FILE" ]] || fail "diagnostics config unavailable"
[[ -s "$TOKEN_FILE" && ! -L "$TOKEN_FILE" ]] || fail "diagnostics token unavailable"
systemctl is-active --quiet "$BROKER_SERVICE" || fail "ops broker inactive"
systemctl is-active --quiet "$AGENT_TIMER" || fail "ops agent timer inactive"
[[ "$(systemctl show "$AGENT_SERVICE" -p NoNewPrivileges --value)" == yes ]] || fail "agent NoNewPrivileges regression"
[[ -S "$BROKER_SOCKET" ]] || fail "broker socket unavailable"
[[ "$(stat -Lc '%U:%G:%a' "$BROKER_SOCKET")" == "root:ccdiag:660" ]] || fail "broker socket boundary rejected"
if [[ "$MODE" == self-test ]]; then
  printf 'OPS_AGENT_STAGING_UPDATER=READY\n'
  printf 'ROOT_BOUNDARY=restricted-sudo-wrapper\n'
  exit 0
fi

[[ "$PACKAGE" =~ ^/tmp/control-center-ops-agent-staging-[0-9a-f]{40}/control-center-ops-agent-staging\.tar\.gz$ ]] \
  || fail "package path rejected"
[[ -f "$PACKAGE" && ! -L "$PACKAGE" ]] || fail "package is not a regular file"
[[ "$(stat -c '%U' -- "$PACKAGE")" == "$STAGING_USER" ]] || fail "package owner rejected"
[[ "$(stat -c '%h' -- "$PACKAGE")" == 1 ]] || fail "package hard-link count rejected"
resolved="$(realpath -e -- "$PACKAGE")"
[[ "$resolved" == "$PACKAGE" ]] || fail "package path is not canonical"
package_size="$(stat -c '%s' -- "$PACKAGE")"
[[ "$package_size" =~ ^[0-9]+$ ]] && (( package_size > 0 && package_size <= MAX_PACKAGE_BYTES )) || fail "package size rejected"

install -d -o root -g root -m 0700 "$STAGING_ROOT" "$BACKUP_ROOT"
stage="$(mktemp -d "$STAGING_ROOT/update.XXXXXX")"
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT
python3 - "$PACKAGE" "$stage" "$MAX_AGENT_BYTES" <<'PY'
import pathlib, sys, tarfile
package, target, max_agent_raw = sys.argv[1:]
max_agent = int(max_agent_raw)
expected = ["manifest.json", "manifest.sig", "ccops_agent_v3.py"]
limits = {"manifest.json": 16384, "manifest.sig": 4096, "ccops_agent_v3.py": max_agent}
root = pathlib.Path(target)
# Stream the untrusted compressed archive and stop after the fourth header at
# most. Do not build an unbounded member list and never extract paths as root.
with tarfile.open(package, "r|gz") as tf:
    for expected_name in expected:
        member = tf.next()
        if member is None or member.name != expected_name:
            raise SystemExit("package entries rejected")
        if not member.isfile() or member.size <= 0 or member.size > limits[expected_name]:
            raise SystemExit(f"package member rejected: {expected_name}")
        fh = tf.extractfile(member)
        if fh is None:
            raise SystemExit(f"package member unreadable: {expected_name}")
        data = fh.read(limits[expected_name] + 1)
        if len(data) != member.size or len(data) > limits[expected_name]:
            raise SystemExit(f"package member size mismatch: {expected_name}")
        path = root / expected_name
        path.write_bytes(data)
        path.chmod(0o600)
    if tf.next() is not None:
        raise SystemExit("package entries rejected")
PY

openssl pkeyutl -verify -pubin -inkey "$PUBLIC_KEY" -rawin \
  -in "$stage/manifest.json" -sigfile "$stage/manifest.sig" >/dev/null 2>&1 \
  || fail "manifest signature rejected"

mapfile -t meta < <(python3 - "$stage/manifest.json" "$stage/ccops_agent_v3.py" <<'PY'
import ast, hashlib, json, pathlib, re, sys
manifest_path, agent_path = map(pathlib.Path, sys.argv[1:])
try:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
except (UnicodeDecodeError, json.JSONDecodeError) as exc:
    raise SystemExit("manifest JSON rejected") from exc
required = {
    "schema", "component", "source_repo", "source_commit", "source_path", "source_blob",
    "agent_version", "artifact_sha256", "expected_product_version", "expected_product_commit"
}
if set(manifest) != required or manifest.get("schema") != 1:
    raise SystemExit("manifest schema rejected")
if manifest.get("component") != "control-center-ops-agent":
    raise SystemExit("component rejected")
if manifest.get("source_repo") != "ControlCenterSoft/control-center-server-diagnostics":
    raise SystemExit("source repository rejected")
if manifest.get("source_path") != "agent/ccops_agent_v3.py":
    raise SystemExit("source path rejected")
hex40 = re.compile(r"[0-9a-f]{40}")
hex64 = re.compile(r"[0-9a-f]{64}")
if not isinstance(manifest.get("source_commit"), str) or not hex40.fullmatch(manifest["source_commit"]):
    raise SystemExit("source commit rejected")
if not isinstance(manifest.get("source_blob"), str) or not hex40.fullmatch(manifest["source_blob"]):
    raise SystemExit("source blob rejected")
if not isinstance(manifest.get("artifact_sha256"), str) or not hex64.fullmatch(manifest["artifact_sha256"]):
    raise SystemExit("artifact digest rejected")
if not isinstance(manifest.get("agent_version"), str) or not re.fullmatch(r"1\.1\.[0-9]+", manifest["agent_version"]):
    raise SystemExit("agent version rejected")
if not isinstance(manifest.get("expected_product_version"), str) or not re.fullmatch(r"1\.1\.0-rc\.[0-9]+", manifest["expected_product_version"]):
    raise SystemExit("product version rejected")
if not isinstance(manifest.get("expected_product_commit"), str) or not hex40.fullmatch(manifest["expected_product_commit"]):
    raise SystemExit("product commit rejected")
raw = agent_path.read_bytes()
if hashlib.sha256(raw).hexdigest() != manifest["artifact_sha256"]:
    raise SystemExit("artifact SHA-256 mismatch")
git_blob = hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
if git_blob != manifest["source_blob"]:
    raise SystemExit("Git blob identity mismatch")
try:
    tree = ast.parse(raw.decode("utf-8", errors="strict"), filename=str(agent_path))
except (UnicodeDecodeError, SyntaxError) as exc:
    raise SystemExit("agent source rejected") from exc
version = None
for node in tree.body:
    if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "AGENT_VERSION" for t in node.targets):
        if isinstance(node.value, ast.Constant) and isinstance(node.value.value, str):
            version = node.value.value
        break
if version != manifest["agent_version"]:
    raise SystemExit("agent source version mismatch")
for key in ("source_commit", "source_blob", "agent_version", "artifact_sha256", "expected_product_version", "expected_product_commit"):
    print(manifest[key])
PY
)
((${#meta[@]} == 6)) || fail "validated manifest metadata unavailable"
source_commit="${meta[0]}"; source_blob="${meta[1]}"; agent_version="${meta[2]}"; artifact_sha256="${meta[3]}"
expected_product_version="${meta[4]}"; expected_product_commit="${meta[5]}"
[[ "$PACKAGE" == "/tmp/control-center-ops-agent-staging-$source_commit/control-center-ops-agent-staging.tar.gz" ]] \
  || fail "package path/source commit binding rejected"

read_product_identity() {
  local version_json
  curl -fsS --max-time 5 http://127.0.0.1:8876/api/v1/health >/dev/null || return 1
  curl -fsS --max-time 5 http://127.0.0.1:8876/api/v1/readiness | grep -Fq '"ready":true' || return 1
  version_json="$(curl -fsS --max-time 5 http://127.0.0.1:8876/api/v1/version)" || return 1
  python3 - "$version_json" "$expected_product_version" "$expected_product_commit" <<'PY'
import json, sys
payload = json.loads(sys.argv[1])
raise SystemExit(0 if payload.get("version") == sys.argv[2] and payload.get("commit") == sys.argv[3] else 1)
PY
}
read_product_identity || fail "test-server product identity/preflight rejected"

current_sha="$(sha256sum "$AGENT_FILE" | awk '{print $1}')"
current_stat="$(stat -c '%U:%G:%a' "$AGENT_FILE")"
if [[ "$current_sha" == "$artifact_sha256" && "$current_stat" == "root:root:755" ]]; then
  printf 'OPS_AGENT_EXACT_ACTIVE=PASSED version=%s source_commit=%s source_blob=%s\n' "$agent_version" "$source_commit" "$source_blob"
  exit 0
fi

backup_dir="$BACKUP_ROOT/update-${source_commit}-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -o root -g root -m 0700 "$backup_dir"
install -o root -g root -m 0755 "$AGENT_FILE" "$backup_dir/ccops_agent_v3.py"
sha256sum "$backup_dir/ccops_agent_v3.py" > "$backup_dir/ccops_agent_v3.py.sha256"
installed_new=0
restore_timer=0
rollback_agent() {
  local rc=$?
  if (( installed_new )); then
    install -o root -g root -m 0755 "$backup_dir/ccops_agent_v3.py" "$AGENT_FILE" || true
    python3 -m py_compile "$AGENT_FILE" >/dev/null 2>&1 || true
    runuser -u "$AGENT_USER" -- /usr/bin/python3 "$AGENT_FILE" --register --state-dir "$STATE_DIR" >/dev/null 2>&1 || true
    printf 'OPS_AGENT_STAGE_ROLLBACK=RESTORED\n' >&2
  fi
  if (( restore_timer )); then systemctl start "$AGENT_TIMER" >/dev/null 2>&1 || true; fi
  exit "$rc"
}
trap rollback_agent ERR

# Avoid replacing code while a timer-triggered oneshot is running. Stopping the
# timer is reversible and does not alter its enabled state. The ERR trap is
# already armed so a quiesce failure restores the timer before exiting.
systemctl stop "$AGENT_TIMER"
restore_timer=1
for _ in {1..30}; do
  systemctl is-active --quiet "$AGENT_SERVICE" || break
  sleep 0.5
done
systemctl is-active --quiet "$AGENT_SERVICE" && fail "ops agent service remained active during quiesce"

tmp_agent="$(mktemp "$(dirname "$AGENT_FILE")/.ccops_agent_v3.py.XXXXXX")"
install -o root -g root -m 0755 "$stage/ccops_agent_v3.py" "$tmp_agent"
mv -f -- "$tmp_agent" "$AGENT_FILE"
installed_new=1
python3 -m py_compile "$AGENT_FILE"
[[ "$(sha256sum "$AGENT_FILE" | awk '{print $1}')" == "$artifact_sha256" ]] || fail "installed agent digest mismatch"
[[ "$(stat -c '%U:%G:%a' "$AGENT_FILE")" == "root:root:755" ]] || fail "installed agent ownership/mode rejected"
runuser -u "$AGENT_USER" -- /usr/bin/python3 "$AGENT_FILE" --register --state-dir "$STATE_DIR"
systemctl is-active --quiet "$BROKER_SERVICE" || fail "broker inactive after agent update"
[[ "$(systemctl show "$AGENT_SERVICE" -p NoNewPrivileges --value)" == yes ]] || fail "agent NoNewPrivileges lost after update"
[[ "$(stat -Lc '%U:%G:%a' "$BROKER_SOCKET")" == "root:ccdiag:660" ]] || fail "broker socket boundary changed"
read_product_identity || fail "product identity/readiness changed after agent update"
systemctl start "$AGENT_TIMER"
systemctl is-active --quiet "$AGENT_TIMER" || fail "timer inactive after agent update"
restore_timer=0
installed_new=0
printf 'OPS_AGENT_STAGE=PASSED version=%s source_commit=%s source_blob=%s\n' "$agent_version" "$source_commit" "$source_blob"
printf 'ARBITRARY_SHELL=disabled\n'
printf 'ROOT_BOUNDARY=unix-so-peercred-root-broker\n'
WRAPPER

# Bind the embedded updater to the actual configured staging account without
# changing its strict package/source/manifest checks.
python3 - "$work/control-center-ops-agent-staging-update" "$STAGING_USER" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
user = sys.argv[2]
text = path.read_text(encoding="utf-8")
needle = 'STAGING_USER="control-center-staging"'
if text.count(needle) != 1:
    raise SystemExit("embedded staging user marker missing")
path.write_text(text.replace(needle, f'STAGING_USER="{user}"', 1), encoding="utf-8")
PY
bash -n "$work/control-center-ops-agent-staging-update"
install -o root -g root -m 0755 "$work/control-center-ops-agent-staging-update" "$UPDATER"
printf '%s ALL=(root) NOPASSWD: %s\n' "$STAGING_USER" "$UPDATER" > "$work/sudoers"
visudo -cf "$work/sudoers" >/dev/null || fail "generated sudoers rule invalid"
install -o root -g root -m 0440 "$work/sudoers" "$SUDOERS"
runuser -u "$STAGING_USER" -- sudo -n "$UPDATER" --self-test >/dev/null \
  || fail "restricted ops-agent staging sudo path failed self-test"

trap - ERR
rm -rf -- "$work"
printf 'OPS_AGENT_STAGING_BOOTSTRAP=INSTALLED\n'
printf 'SUDO_SCOPE=control-center-ops-agent-staging-update-only\n'
printf 'GENERAL_PASSWORDLESS_SUDO=disabled\n'