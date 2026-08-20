#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

REPO="${CONTROL_CENTER_GITHUB_REPO:-ControlCenterSoft/srv-deployment}"
STAGING_USER="${CONTROL_CENTER_STAGING_USER:-control-center-staging}"
UPDATER="${CONTROL_CENTER_UPDATER:-/usr/local/sbin/control-center-update}"
STAGING_UPDATER="${CONTROL_CENTER_STAGING_UPDATER:-/usr/local/sbin/control-center-staging-update}"
STAGING_PUBLIC_KEY="${CONTROL_CENTER_STAGING_PUBLIC_KEY:-/etc/control-center/staging-update-public.pem}"
STATE_DIR="${CONTROL_CENTER_STAGING_STATE_DIR:-/var/lib/control-center-staging-bootstrap}"
SSH_PORT="${CONTROL_CENTER_STAGING_PORT:-}"
STAGING_HOST="${CONTROL_CENTER_STAGING_HOST:-}"

fail() {
  printf 'STAGING_BOOTSTRAP_FAILED: %s\n' "$*" >&2
  exit 1
}

[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "run as root"
[[ "$STAGING_USER" =~ ^[a-z_][a-z0-9_-]{0,30}$ ]] || fail "invalid staging user"
[[ -x "$UPDATER" ]] || fail "updater is missing: $UPDATER"
command -v apt-get >/dev/null 2>&1 || fail "apt-get is required on the test server"

need_packages=()
command -v gh >/dev/null 2>&1 || need_packages+=(gh)
command -v sudo >/dev/null 2>&1 || need_packages+=(sudo)
command -v visudo >/dev/null 2>&1 || need_packages+=(sudo)
command -v sshd >/dev/null 2>&1 || need_packages+=(openssh-server)
if ((${#need_packages[@]})); then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq "${need_packages[@]}" >/dev/null
fi

for bin in curl git gh openssl ssh-keygen ssh sshd sudo visudo systemctl python3 sed awk install mktemp getent useradd realpath stat; do
  command -v "$bin" >/dev/null 2>&1 || fail "missing required command after bootstrap package install: $bin"
done

if systemctl list-unit-files ssh.service >/dev/null 2>&1; then
  systemctl enable --now ssh.service >/dev/null
elif systemctl list-unit-files sshd.service >/dev/null 2>&1; then
  systemctl enable --now sshd.service >/dev/null
else
  fail "OpenSSH server systemd unit is unavailable"
fi

resolve_token() {
  if [[ -n "${GH_TOKEN:-}" ]]; then
    printf '%s' "$GH_TOKEN"
    return 0
  fi
  local credential password
  credential="$(
    GIT_TERMINAL_PROMPT=0 timeout 8s git credential fill 2>/dev/null <<EOF || true
protocol=https
host=github.com
path=${REPO}.git

EOF
  )"
  password="$(printf '%s\n' "$credential" | sed -n 's/^password=//p' | head -n1)"
  unset credential
  [[ -n "$password" ]] || return 1
  printf '%s' "$password"
}

TOKEN="$(resolve_token || true)"
[[ -n "$TOKEN" ]] || fail "no GitHub credential found; export GH_TOKEN with repository admin + Actions secrets write access and rerun"
export GH_TOKEN="$TOKEN"
unset TOKEN

gh api "repos/$REPO" >/dev/null || fail "GitHub credential cannot access $REPO"
gh api --method PATCH "repos/$REPO" -F allow_auto_merge=true >/dev/null \
  || fail "GitHub credential cannot enable repository auto-merge; Administration(write) is required"
[[ "$(gh api "repos/$REPO" --jq '.allow_auto_merge')" == true ]] \
  || fail "GitHub did not persist allow_auto_merge=true"

if [[ -z "$SSH_PORT" ]]; then
  SSH_PORT="$(sshd -T 2>/dev/null | awk '$1=="port" {print $2; exit}')"
fi
[[ "$SSH_PORT" =~ ^[0-9]{1,5}$ ]] || fail "invalid SSH port: $SSH_PORT"
((10#$SSH_PORT >= 1 && 10#$SSH_PORT <= 65535)) || fail "SSH port out of range"

if [[ -z "$STAGING_HOST" ]]; then
  STAGING_HOST="$(curl -4 -fsS --max-time 10 https://api.ipify.org 2>/dev/null || true)"
fi
if [[ -z "$STAGING_HOST" ]]; then
  STAGING_HOST="$(curl -4 -fsS --max-time 10 https://ifconfig.me/ip 2>/dev/null || true)"
fi
[[ "$STAGING_HOST" =~ ^[A-Za-z0-9._:-]+$ ]] \
  || fail "could not determine a safe public staging host; set CONTROL_CENTER_STAGING_HOST explicitly"

if ! id "$STAGING_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$STAGING_USER"
fi
home_dir="$(getent passwd "$STAGING_USER" | cut -d: -f6)"
[[ -n "$home_dir" && -d "$home_dir" ]] || fail "staging user home is unavailable"

work="$(mktemp -d /tmp/control-center-staging-bootstrap.XXXXXX)"
cleanup() {
  rm -rf -- "$work"
  unset GH_TOKEN
}
trap cleanup EXIT

ssh_key="$work/id_control_center_staging"
ssh-keygen -q -t ed25519 -N '' -C 'control-center-github-actions-staging' -f "$ssh_key"

install -d -m 0700 -o "$STAGING_USER" -g "$STAGING_USER" "$home_dir/.ssh"
authorized="$home_dir/.ssh/authorized_keys"
tmp_authorized="$work/authorized_keys"
[[ -f "$authorized" ]] && cat "$authorized" > "$tmp_authorized"
pub_line="$(cat "$ssh_key.pub")"
key_material="$(awk '{print $2}' <<<"$pub_line")"
if [[ -s "$tmp_authorized" ]]; then
  grep -v 'control-center-github-actions-staging$' "$tmp_authorized" > "$tmp_authorized.new" || true
  mv "$tmp_authorized.new" "$tmp_authorized"
fi
printf 'no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty %s\n' "$pub_line" >> "$tmp_authorized"
install -m 0600 -o "$STAGING_USER" -g "$STAGING_USER" "$tmp_authorized" "$authorized"

# One dedicated staging signing key. Its public half is pinned on the server;
# the private half is uploaded to Actions. The SSH user cannot choose another trust key.
signing_key="$work/staging-signing-private.pem"
openssl genpkey -algorithm ED25519 -out "$signing_key"
chmod 0600 "$signing_key"
install -d -m 0755 -o root -g root "$(dirname "$STAGING_PUBLIC_KEY")"
openssl pkey -in "$signing_key" -pubout -out "$work/staging-signing-public.pem"
install -m 0644 -o root -g root "$work/staging-signing-public.pem" "$STAGING_PUBLIC_KEY"

cat > "$work/control-center-staging-update" <<'WRAPPER'
#!/usr/bin/env bash
set -Eeuo pipefail
UPDATER=/usr/local/sbin/control-center-update
PUBLIC_KEY=/etc/control-center/staging-update-public.pem
if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
  [[ $EUID -eq 0 && -x "$UPDATER" && -s "$PUBLIC_KEY" ]]
  exit
fi
[[ $EUID -eq 0 ]] || { echo 'staging updater must run as root' >&2; exit 1; }
[[ $# -eq 2 && "$1" == --package ]] || { echo 'usage: control-center-staging-update --package PATH' >&2; exit 2; }
package="$2"
[[ "$package" =~ ^/tmp/control-center-staging-[0-9a-f]{40}/control-center-staging\.tar\.gz$ ]] \
  || { echo 'staging package path rejected' >&2; exit 2; }
[[ -f "$package" && ! -L "$package" ]] || { echo 'staging package is invalid' >&2; exit 2; }
resolved="$(realpath -e -- "$package")"
[[ "$resolved" == "$package" ]] || { echo 'staging package path is not canonical' >&2; exit 2; }
owner="$(stat -c '%U' -- "$package")"
[[ "$owner" == control-center-staging ]] || { echo 'staging package owner rejected' >&2; exit 2; }
exec "$UPDATER" --package "$package" --public-key "$PUBLIC_KEY"
WRAPPER
install -m 0755 -o root -g root "$work/control-center-staging-update" "$STAGING_UPDATER"

sudoers="/etc/sudoers.d/control-center-staging"
printf '%s ALL=(root) NOPASSWD: %s\n' "$STAGING_USER" "$STAGING_UPDATER" > "$work/sudoers"
visudo -cf "$work/sudoers" >/dev/null || fail "generated sudoers rule is invalid"
install -m 0440 -o root -g root "$work/sudoers" "$sudoers"

ssh-keygen -A >/dev/null 2>&1 || true
host_key_pub="/etc/ssh/ssh_host_ed25519_key.pub"
[[ -s "$host_key_pub" ]] || fail "ED25519 SSH host key is unavailable"
host_key_type="$(awk '{print $1}' "$host_key_pub")"
host_key_data="$(awk '{print $2}' "$host_key_pub")"
[[ "$host_key_type" == ssh-ed25519 && -n "$host_key_data" ]] || fail "invalid ED25519 SSH host key"
known_host_name="$STAGING_HOST"
[[ "$SSH_PORT" == 22 ]] || known_host_name="[$STAGING_HOST]:$SSH_PORT"
printf '%s %s %s\n' "$known_host_name" "$host_key_type" "$host_key_data" > "$work/known_hosts"

ssh -i "$ssh_key" \
  -p "$SSH_PORT" \
  -o BatchMode=yes \
  -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ConnectTimeout=8 \
  "$STAGING_USER@127.0.0.1" \
  "sudo -n '$STAGING_UPDATER' --self-test" \
  || fail "new staging SSH identity or restricted sudo path failed local acceptance"

set_secret_body() {
  local name="$1" value="$2"
  gh secret set "$name" --repo "$REPO" --body "$value" >/dev/null \
    || fail "failed to set GitHub repository secret $name"
}
set_secret_file() {
  local name="$1" file="$2"
  gh secret set "$name" --repo "$REPO" < "$file" >/dev/null \
    || fail "failed to set GitHub repository secret $name"
}

set_secret_body CONTROL_CENTER_STAGING_HOST "$STAGING_HOST"
set_secret_body CONTROL_CENTER_STAGING_USER "$STAGING_USER"
set_secret_file CONTROL_CENTER_STAGING_SSH_KEY "$ssh_key"
set_secret_file CONTROL_CENTER_STAGING_KNOWN_HOSTS "$work/known_hosts"
set_secret_file CONTROL_CENTER_STAGING_SIGNING_KEY "$signing_key"
set_secret_body CONTROL_CENTER_STAGING_PORT "$SSH_PORT"

mapfile -t installed_secrets < <(gh secret list --repo "$REPO" --json name --jq '.[].name')
for required in \
  CONTROL_CENTER_STAGING_HOST \
  CONTROL_CENTER_STAGING_USER \
  CONTROL_CENTER_STAGING_SSH_KEY \
  CONTROL_CENTER_STAGING_KNOWN_HOSTS \
  CONTROL_CENTER_STAGING_SIGNING_KEY \
  CONTROL_CENTER_STAGING_PORT; do
  printf '%s\n' "${installed_secrets[@]}" | grep -Fxq "$required" \
    || fail "GitHub did not report repository secret $required after upload"
done

install -d -m 0700 -o root -g root "$STATE_DIR"
python3 - "$STATE_DIR/state.json" "$REPO" "$STAGING_HOST" "$STAGING_USER" "$SSH_PORT" "$key_material" <<'PY'
import hashlib
import json
import sys
from datetime import datetime, timezone
path, repo, host, user, port, key_material = sys.argv[1:]
payload = {
    "schema": 2,
    "configured_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    "repository": repo,
    "staging_host": host,
    "staging_user": user,
    "staging_port": int(port),
    "authorized_key_material_sha256": hashlib.sha256(key_material.encode()).hexdigest(),
    "allow_auto_merge": True,
    "server_pinned_staging_trust": True,
    "secrets_configured": [
        "CONTROL_CENTER_STAGING_HOST",
        "CONTROL_CENTER_STAGING_USER",
        "CONTROL_CENTER_STAGING_SSH_KEY",
        "CONTROL_CENTER_STAGING_KNOWN_HOSTS",
        "CONTROL_CENTER_STAGING_SIGNING_KEY",
        "CONTROL_CENTER_STAGING_PORT",
    ],
}
with open(path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
PY
chmod 0600 "$STATE_DIR/state.json"

printf 'STAGING_BOOTSTRAP=PASSED\n'
printf 'BOOTSTRAP_SCHEMA=2\n'
printf 'REPOSITORY=%s\n' "$REPO"
printf 'ALLOW_AUTO_MERGE=true\n'
printf 'STAGING_USER=%s\n' "$STAGING_USER"
printf 'STAGING_PORT=%s\n' "$SSH_PORT"
printf 'STAGING_SECRETS=CONFIGURED\n'
printf 'SERVER_PINNED_STAGING_TRUST=true\n'
printf 'PRIVATE_VALUES=NOT_PRINTED\n'
