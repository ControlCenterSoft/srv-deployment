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

ssh "${ssh_opts[@]}" "$remote" "install -d -m 0700 '$remote_dir'"
scp "${scp_opts[@]}" "$PACKAGE" "$PUBLIC_KEY" "$remote:$remote_dir/"

package_name="$(basename "$PACKAGE")"
key_name="$(basename "$PUBLIC_KEY")"
[[ "$package_name" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "invalid package basename" >&2; exit 2; }
[[ "$key_name" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "invalid key basename" >&2; exit 2; }

ssh "${ssh_opts[@]}" "$remote" \
  "sudo /usr/local/sbin/control-center-update --package '$remote_dir/$package_name' --public-key '$remote_dir/$key_name' && \
   curl -fsS http://127.0.0.1:8876/api/v1/health >/dev/null && \
   curl -fsS http://127.0.0.1:8876/api/v1/readiness | grep -Fq '\"ready\":true' && \
   curl -fsS http://127.0.0.1:8876/api/v1/version | grep -Fq '\"version\":\"${CANDIDATE_VERSION}\"'"

echo "STAGING_ACCEPTANCE=PASSED version=${CANDIDATE_VERSION} sha=${CANDIDATE_SHA}"
