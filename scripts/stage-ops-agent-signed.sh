#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

AGENT_FILE=""
SOURCE_COMMIT=""
SOURCE_BLOB=""
AGENT_VERSION=""
EXPECTED_PRODUCT_VERSION=""
EXPECTED_PRODUCT_COMMIT=""
BUILD_ONLY=""
SIGNING_KEY_FILE=""

usage() {
  echo "Usage: $0 --agent-file FILE --source-commit SHA --source-blob BLOB --agent-version VERSION --expected-product-version VERSION --expected-product-commit SHA [--signing-key FILE] [--build-only OUTPUT]" >&2
}
while (($#)); do
  case "$1" in
    --agent-file) AGENT_FILE="${2:-}"; shift 2 ;;
    --source-commit) SOURCE_COMMIT="${2:-}"; shift 2 ;;
    --source-blob) SOURCE_BLOB="${2:-}"; shift 2 ;;
    --agent-version) AGENT_VERSION="${2:-}"; shift 2 ;;
    --expected-product-version) EXPECTED_PRODUCT_VERSION="${2:-}"; shift 2 ;;
    --expected-product-commit) EXPECTED_PRODUCT_COMMIT="${2:-}"; shift 2 ;;
    --signing-key) SIGNING_KEY_FILE="${2:-}"; shift 2 ;;
    --build-only) BUILD_ONLY="${2:-}"; shift 2 ;;
    *) usage; exit 2 ;;
  esac
done
[[ -f "$AGENT_FILE" && ! -L "$AGENT_FILE" ]] || { echo "agent file invalid" >&2; exit 2; }
[[ "$SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || { echo "source commit invalid" >&2; exit 2; }
[[ "$SOURCE_BLOB" =~ ^[0-9a-f]{40}$ ]] || { echo "source blob invalid" >&2; exit 2; }
[[ "$AGENT_VERSION" =~ ^1\.1\.[0-9]+$ ]] || { echo "agent version invalid" >&2; exit 2; }
[[ "$EXPECTED_PRODUCT_VERSION" =~ ^1\.1\.0-rc\.[0-9]+$ ]] || { echo "expected product version invalid" >&2; exit 2; }
[[ "$EXPECTED_PRODUCT_COMMIT" =~ ^[0-9a-f]{40}$ ]] || { echo "expected product commit invalid" >&2; exit 2; }
for bin in awk install mktemp openssl python3 sha256sum tar; do command -v "$bin" >/dev/null || { echo "missing $bin" >&2; exit 2; }; done

work="$(mktemp -d /tmp/control-center-ops-agent-package.XXXXXX)"
cleanup() { rm -rf -- "$work"; }
trap cleanup EXIT
install -m 0600 "$AGENT_FILE" "$work/ccops_agent_v3.py"
artifact_sha="$(sha256sum "$work/ccops_agent_v3.py" | awk '{print $1}')"
python3 - "$work/ccops_agent_v3.py" "$SOURCE_BLOB" "$AGENT_VERSION" <<'PY'
import ast, hashlib, pathlib, sys
path = pathlib.Path(sys.argv[1]); expected_blob = sys.argv[2]; expected_version = sys.argv[3]
raw = path.read_bytes()
blob = hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
if blob != expected_blob:
    raise SystemExit("source blob mismatch")
tree = ast.parse(raw.decode("utf-8", errors="strict"), filename=str(path))
version = None
for node in tree.body:
    if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "AGENT_VERSION" for t in node.targets):
        if isinstance(node.value, ast.Constant) and isinstance(node.value.value, str):
            version = node.value.value
        break
if version != expected_version:
    raise SystemExit("agent version mismatch")
PY
python3 - "$work/manifest.json" "$SOURCE_COMMIT" "$SOURCE_BLOB" "$AGENT_VERSION" "$artifact_sha" "$EXPECTED_PRODUCT_VERSION" "$EXPECTED_PRODUCT_COMMIT" <<'PY'
import json, pathlib, sys
path, commit, blob, version, digest, product_version, product_commit = sys.argv[1:]
payload = {
    "schema": 1,
    "component": "control-center-ops-agent",
    "source_repo": "ControlCenterSoft/control-center-server-diagnostics",
    "source_commit": commit,
    "source_path": "agent/ccops_agent_v3.py",
    "source_blob": blob,
    "agent_version": version,
    "artifact_sha256": digest,
    "expected_product_version": product_version,
    "expected_product_commit": product_commit,
}
pathlib.Path(path).write_text(json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
PY

if [[ -z "$SIGNING_KEY_FILE" ]]; then
  [[ -n "${CONTROL_CENTER_STAGING_SIGNING_KEY:-}" ]] || { echo "staging signing key unavailable" >&2; exit 2; }
  SIGNING_KEY_FILE="$work/signing-private.pem"
  printf '%s\n' "$CONTROL_CENTER_STAGING_SIGNING_KEY" > "$SIGNING_KEY_FILE"
  chmod 0600 "$SIGNING_KEY_FILE"
fi
[[ -f "$SIGNING_KEY_FILE" && ! -L "$SIGNING_KEY_FILE" ]] || { echo "signing key file invalid" >&2; exit 2; }
openssl pkey -in "$SIGNING_KEY_FILE" -noout >/dev/null 2>&1 || { echo "signing key malformed" >&2; exit 2; }
openssl pkeyutl -sign -rawin -inkey "$SIGNING_KEY_FILE" -in "$work/manifest.json" -out "$work/manifest.sig"
package="$work/control-center-ops-agent-staging.tar.gz"
tar -czf "$package" -C "$work" manifest.json manifest.sig ccops_agent_v3.py
expected_entries=$'manifest.json\nmanifest.sig\nccops_agent_v3.py'
[[ "$(tar -tzf "$package")" == "$expected_entries" ]] || { echo "package entries invalid" >&2; exit 2; }

if [[ -n "$BUILD_ONLY" ]]; then
  [[ ! -d "$BUILD_ONLY" ]] || { echo "build-only output must be a file path" >&2; exit 2; }
  install -m 0600 "$package" "$BUILD_ONLY"
  printf 'OPS_AGENT_PACKAGE=BUILT source_commit=%s source_blob=%s agent_version=%s\n' "$SOURCE_COMMIT" "$SOURCE_BLOB" "$AGENT_VERSION"
  exit 0
fi

: "${CONTROL_CENTER_STAGING_HOST:?CONTROL_CENTER_STAGING_HOST is required}"
: "${CONTROL_CENTER_STAGING_USER:?CONTROL_CENTER_STAGING_USER is required}"
: "${CONTROL_CENTER_STAGING_SSH_KEY_FILE:?CONTROL_CENTER_STAGING_SSH_KEY_FILE is required}"
: "${CONTROL_CENTER_STAGING_KNOWN_HOSTS_FILE:?CONTROL_CENTER_STAGING_KNOWN_HOSTS_FILE is required}"
STAGING_PORT="${CONTROL_CENTER_STAGING_PORT:-22}"
[[ "$CONTROL_CENTER_STAGING_HOST" =~ ^[A-Za-z0-9._:-]+$ ]] || { echo "staging host invalid" >&2; exit 2; }
[[ "$CONTROL_CENTER_STAGING_USER" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "staging user invalid" >&2; exit 2; }
[[ "$STAGING_PORT" =~ ^[0-9]{1,5}$ ]] && ((10#$STAGING_PORT >= 1 && 10#$STAGING_PORT <= 65535)) || { echo "staging port invalid" >&2; exit 2; }
[[ -f "$CONTROL_CENTER_STAGING_SSH_KEY_FILE" && -f "$CONTROL_CENTER_STAGING_KNOWN_HOSTS_FILE" ]] || { echo "staging SSH material missing" >&2; exit 2; }
for bin in curl scp ssh stat systemctl; do command -v "$bin" >/dev/null || { echo "missing $bin" >&2; exit 2; }; done
remote="${CONTROL_CENTER_STAGING_USER}@${CONTROL_CENTER_STAGING_HOST}"
remote_dir="/tmp/control-center-ops-agent-staging-${SOURCE_COMMIT}"
remote_package="$remote_dir/control-center-ops-agent-staging.tar.gz"
ssh_opts=(
  -i "$CONTROL_CENTER_STAGING_SSH_KEY_FILE" -p "$STAGING_PORT" -o BatchMode=yes -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$CONTROL_CENTER_STAGING_KNOWN_HOSTS_FILE" -o ConnectTimeout=10
)
scp_opts=(
  -i "$CONTROL_CENTER_STAGING_SSH_KEY_FILE" -P "$STAGING_PORT" -o BatchMode=yes -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$CONTROL_CENTER_STAGING_KNOWN_HOSTS_FILE" -o ConnectTimeout=10
)
cleanup_remote() { ssh "${ssh_opts[@]}" "$remote" "rm -rf '$remote_dir'" >/dev/null 2>&1 || true; }
trap 'cleanup_remote; cleanup' EXIT

# Read-only preflight before package upload or sudo mutation.
ssh "${ssh_opts[@]}" "$remote" \
  "systemctl is-active --quiet control-center-ops-broker.service && \
   systemctl is-active --quiet control-center-ops-agent.timer && \
   test -S /run/control-center-ops/broker.sock && \
   test \"\$(stat -Lc '%U:%G:%a' /run/control-center-ops/broker.sock)\" = 'root:ccdiag:660' && \
   test \"\$(systemctl show control-center-ops-agent.service -p NoNewPrivileges --value)\" = yes && \
   curl -fsS --max-time 5 http://127.0.0.1:8876/api/v1/health >/dev/null && \
   curl -fsS --max-time 5 http://127.0.0.1:8876/api/v1/readiness | grep -Fq '\"ready\":true' && \
   curl -fsS --max-time 5 http://127.0.0.1:8876/api/v1/version | grep -Fq '\"version\":\"$EXPECTED_PRODUCT_VERSION\"' && \
   curl -fsS --max-time 5 http://127.0.0.1:8876/api/v1/version | grep -Fq '\"commit\":\"$EXPECTED_PRODUCT_COMMIT\"' && \
   sudo -n /usr/local/sbin/control-center-ops-agent-staging-update --self-test"
ssh "${ssh_opts[@]}" "$remote" "rm -rf '$remote_dir' && install -d -m 0700 '$remote_dir'"
scp "${scp_opts[@]}" "$package" "$remote:$remote_package"
ssh "${ssh_opts[@]}" "$remote" "chmod 0600 '$remote_package' && sudo -n /usr/local/sbin/control-center-ops-agent-staging-update --package '$remote_package'"
ssh "${ssh_opts[@]}" "$remote" \
  "systemctl is-active --quiet control-center-ops-broker.service && \
   systemctl is-active --quiet control-center-ops-agent.timer && \
   test \"\$(systemctl show control-center-ops-agent.service -p NoNewPrivileges --value)\" = yes && \
   curl -fsS --max-time 5 http://127.0.0.1:8876/api/v1/health >/dev/null && \
   curl -fsS --max-time 5 http://127.0.0.1:8876/api/v1/readiness | grep -Fq '\"ready\":true' && \
   curl -fsS --max-time 5 http://127.0.0.1:8876/api/v1/version | grep -Fq '\"version\":\"$EXPECTED_PRODUCT_VERSION\"' && \
   curl -fsS --max-time 5 http://127.0.0.1:8876/api/v1/version | grep -Fq '\"commit\":\"$EXPECTED_PRODUCT_COMMIT\"'"
printf 'OPS_AGENT_STAGING=PASSED source_commit=%s source_blob=%s agent_version=%s\n' "$SOURCE_COMMIT" "$SOURCE_BLOB" "$AGENT_VERSION"
