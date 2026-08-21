#!/usr/bin/env bash
set -Eeuo pipefail

PACKAGE=""
PUBLIC_KEY=""
CANDIDATE_VERSION=""
CANDIDATE_SHA=""

usage() {
  echo "Usage: $0 --package PATH --public-key PATH --candidate-version VERSION --candidate-sha SHA" >&2
}

while (($#)); do
  case "$1" in
    --package) PACKAGE="${2:-}"; shift 2 ;;
    --public-key) PUBLIC_KEY="${2:-}"; shift 2 ;;
    --candidate-version) CANDIDATE_VERSION="${2:-}"; shift 2 ;;
    --candidate-sha) CANDIDATE_SHA="${2:-}"; shift 2 ;;
    *) usage; exit 2 ;;
  esac
done

[[ -f "$PACKAGE" && ! -L "$PACKAGE" ]] || { echo "staging package is invalid" >&2; exit 2; }
[[ -f "$PUBLIC_KEY" && ! -L "$PUBLIC_KEY" ]] || { echo "staging public key is invalid" >&2; exit 2; }
[[ "$CANDIDATE_VERSION" =~ ^1\.1\.0-rc\.[0-9]+$ ]] || { echo "invalid candidate version" >&2; exit 2; }
[[ "$CANDIDATE_SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "invalid candidate SHA" >&2; exit 2; }

: "${CONTROL_CENTER_STAGING_HOST:?CONTROL_CENTER_STAGING_HOST is required}"
: "${CONTROL_CENTER_STAGING_USER:?CONTROL_CENTER_STAGING_USER is required}"
: "${CONTROL_CENTER_STAGING_SSH_KEY_FILE:?CONTROL_CENTER_STAGING_SSH_KEY_FILE is required}"
: "${CONTROL_CENTER_STAGING_KNOWN_HOSTS_FILE:?CONTROL_CENTER_STAGING_KNOWN_HOSTS_FILE is required}"

STAGING_PORT="${CONTROL_CENTER_STAGING_PORT:-22}"
[[ "$STAGING_PORT" =~ ^[0-9]{1,5}$ ]] && ((10#$STAGING_PORT >= 1 && 10#$STAGING_PORT <= 65535)) || {
  echo "invalid staging SSH port" >&2
  exit 2
}
[[ "$CONTROL_CENTER_STAGING_HOST" =~ ^[A-Za-z0-9._:-]+$ ]] || {
  echo "invalid staging host" >&2
  exit 2
}
[[ "$CONTROL_CENTER_STAGING_USER" =~ ^[A-Za-z0-9._-]+$ ]] || {
  echo "invalid staging user" >&2
  exit 2
}
[[ -f "$CONTROL_CENTER_STAGING_SSH_KEY_FILE" ]] || { echo "SSH key file is missing" >&2; exit 2; }
[[ -f "$CONTROL_CENTER_STAGING_KNOWN_HOSTS_FILE" ]] || { echo "known_hosts file is missing" >&2; exit 2; }

# Validate that the public key artifact is structurally valid. It is evidence only;
# remote trust is pinned by bootstrap at /etc/control-center/staging-update-public.pem.
openssl pkey -pubin -in "$PUBLIC_KEY" -noout >/dev/null 2>&1 \
  || { echo "staging public key is malformed" >&2; exit 2; }

remote="${CONTROL_CENTER_STAGING_USER}@${CONTROL_CENTER_STAGING_HOST}"
remote_dir="/tmp/control-center-staging-${CANDIDATE_SHA}"
ssh_opts=(
  -i "$CONTROL_CENTER_STAGING_SSH_KEY_FILE"
  -p "$STAGING_PORT"
  -o BatchMode=yes
  -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=yes
  -o "UserKnownHostsFile=$CONTROL_CENTER_STAGING_KNOWN_HOSTS_FILE"
  -o ConnectTimeout=10
)
scp_opts=(
  -i "$CONTROL_CENTER_STAGING_SSH_KEY_FILE"
  -P "$STAGING_PORT"
  -o BatchMode=yes
  -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=yes
  -o "UserKnownHostsFile=$CONTROL_CENTER_STAGING_KNOWN_HOSTS_FILE"
  -o ConnectTimeout=10
)

cleanup_remote() {
  ssh "${ssh_opts[@]}" "$remote" "rm -rf '$remote_dir'" >/dev/null 2>&1 || true
}
trap cleanup_remote EXIT

# A previous attempt may have switched the exact signed candidate successfully and
# then lost CI connectivity or failed outside the updater. Resume only when the
# complete operational identity is already exact. Version alone is insufficient:
# the commit, dual-runtime worker state, socket boundary, health and readiness must
# all match before package application is skipped. Any mismatch falls through to
# the restricted signed updater, preserving fail-closed same-version drift handling.
if ssh "${ssh_opts[@]}" "$remote" \
  "systemctl is-active --quiet control-center-privileged-worker.service && \
   systemctl is-enabled --quiet control-center-privileged-worker.service && \
   test -S /run/control-center/privileged-worker.sock && \
   test \"\$(stat -Lc '%U:%G:%a' /run/control-center/privileged-worker.sock)\" = 'root:control-center:660' && \
   curl -fsS http://127.0.0.1:8876/api/v1/health >/dev/null && \
   curl -fsS http://127.0.0.1:8876/api/v1/readiness | grep -Fq '\"ready\":true' && \
   curl -fsS http://127.0.0.1:8876/api/v1/version | grep -Fq '\"version\":\"${CANDIDATE_VERSION}\"' && \
   curl -fsS http://127.0.0.1:8876/api/v1/version | grep -Fq '\"commit\":\"${CANDIDATE_SHA}\"'"; then
  echo "STAGING_EXACT_ACTIVE=PASSED version=${CANDIDATE_VERSION} sha=${CANDIDATE_SHA} dual_runtime=true"
  echo "STAGING_ACCEPTANCE=PASSED version=${CANDIDATE_VERSION} sha=${CANDIDATE_SHA} dual_runtime=true"
  exit 0
fi

ssh "${ssh_opts[@]}" "$remote" "install -d -m 0700 '$remote_dir'"
scp "${scp_opts[@]}" "$PACKAGE" "$remote:$remote_dir/control-center-staging.tar.gz"

ssh "${ssh_opts[@]}" "$remote" \
  "sudo -n /usr/local/sbin/control-center-staging-update --package '$remote_dir/control-center-staging.tar.gz' && \
   systemctl is-active --quiet control-center-privileged-worker.service && \
   systemctl is-enabled --quiet control-center-privileged-worker.service && \
   test -S /run/control-center/privileged-worker.sock && \
   test \"\$(stat -Lc '%U:%G:%a' /run/control-center/privileged-worker.sock)\" = 'root:control-center:660' && \
   curl -fsS http://127.0.0.1:8876/api/v1/health >/dev/null && \
   curl -fsS http://127.0.0.1:8876/api/v1/readiness | grep -Fq '\"ready\":true' && \
   curl -fsS http://127.0.0.1:8876/api/v1/version | grep -Fq '\"version\":\"${CANDIDATE_VERSION}\"' && \
   curl -fsS http://127.0.0.1:8876/api/v1/version | grep -Fq '\"commit\":\"${CANDIDATE_SHA}\"'"

echo "STAGING_ACCEPTANCE=PASSED version=${CANDIDATE_VERSION} sha=${CANDIDATE_SHA} dual_runtime=true"
