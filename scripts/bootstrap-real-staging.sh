#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

REPO="${CONTROL_CENTER_GITHUB_REPO:-ControlCenterSoft/srv-deployment}"
STAGING_USER="${CONTROL_CENTER_STAGING_USER:-control-center-staging}"
UPDATER="${CONTROL_CENTER_UPDATER:-/usr/local/sbin/control-center-update}"
STAGING_UPDATER="${CONTROL_CENTER_STAGING_UPDATER:-/usr/local/sbin/control-center-staging-update}"
STAGING_PUBLIC_KEY="${CONTROL_CENTER_STAGING_PUBLIC_KEY:-/etc/control-center/staging-update-public.pem}"
STATE_DIR="${CONTROL_CENTER_STAGING_STATE_DIR:-/var/lib/control-center-staging-bootstrap}"
CREDENTIAL_DIR="$STATE_DIR/credentials"
SSH_PORT="${CONTROL_CENTER_STAGING_PORT:-}"
STAGING_HOST="${CONTROL_CENTER_STAGING_HOST:-}"
CURRENT_STAGE="preflight"

fail() {
  printf 'STAGING_BOOTSTRAP_FAILED stage=%s: %s\n' "$CURRENT_STAGE" "$*" >&2
  exit 1
}

on_err() {
  local rc=$?
  printf 'STAGING_BOOTSTRAP_FAILED stage=%s line=%s rc=%s\n' "$CURRENT_STAGE" "${BASH_LINENO[0]:-unknown}" "$rc" >&2
  exit "$rc"
}
trap on_err ERR

stage() {
  CURRENT_STAGE="$1"
  printf 'STAGING_BOOTSTRAP_STAGE=%s\n' "$CURRENT_STAGE"
}

[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "run as root"
[[ "$STAGING_USER" =~ ^[a-z_][a-z0-9_-]{0,30}$ ]] || fail "invalid staging user"
[[ -x "$UPDATER" ]] || fail "updater is missing: $UPDATER"
command -v apt-get >/dev/null 2>&1 || fail "apt-get is required on the test server"

stage packages
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

for bin in curl git gh openssl ssh-keygen ssh sshd sudo visudo systemctl python3 sed awk install mktemp getent useradd realpath stat timeout grep cut head; do
  command -v "$bin" >/dev/null 2>&1 || fail "missing required command after package install: $bin"
done

if systemctl list-unit-files ssh.service --no-legend 2>/dev/null | grep -q '^ssh\.service'; then
  systemctl enable --now ssh.service >/dev/null
elif systemctl list-unit-files sshd.service --no-legend 2>/dev/null | grep -q '^sshd\.service'; then
  systemctl enable --now sshd.service >/dev/null
else
  fail "OpenSSH server systemd unit is unavailable"
fi

resolve_existing_token() {
  local token credential
  if [[ -n "${GH_TOKEN:-}" ]]; then
    printf '%s' "$GH_TOKEN"
    return 0
  fi
  if token="$(gh auth token -h github.com 2>/dev/null)" && [[ -n "$token" ]]; then
    printf '%s' "$token"
    return 0
  fi
  credential="$(
    GIT_TERMINAL_PROMPT=0 timeout 8s git credential fill 2>/dev/null <<EOF || true
protocol=https
host=github.com
path=${REPO}.git

EOF
  )"
  token="$(printf '%s\n' "$credential" | sed -n 's/^password=//p' | head -n1)"
  unset credential
  [[ -n "$token" ]] || return 1
  printf '%s' "$token"
}

stage github-auth
TOKEN="$(resolve_existing_token || true)"
if [[ -n "$TOKEN" ]]; then
  export GH_TOKEN="$TOKEN"
fi
unset TOKEN

have_repo_access=false
have_secret_access=false
if gh api "repos/$REPO" >/dev/null 2>&1; then
  have_repo_access=true
fi
if [[ "$have_repo_access" == true ]] && gh api "repos/$REPO/actions/secrets" >/dev/null 2>&1; then
  have_secret_access=true
fi

if [[ "$have_secret_access" != true ]]; then
  printf 'GITHUB_SECRET_AUTH_REQUIRED=1\n'
  printf 'GITHUB_AUTH_ACTION=Complete the GitHub device authorization shown below; no token needs to be copied into this terminal.\n'
  unset GH_TOKEN GITHUB_TOKEN
  if gh auth status -h github.com >/dev/null 2>&1; then
    gh auth refresh -h github.com -s repo
  else
    gh auth login -h github.com -p https -w --skip-ssh-key
  fi
  TOKEN="$(gh auth token -h github.com 2>/dev/null || true)"
  [[ -n "$TOKEN" ]] || fail "GitHub CLI authentication completed without a usable token"
  export GH_TOKEN="$TOKEN"
  unset TOKEN
fi

gh api "repos/$REPO" >/dev/null || fail "GitHub credential cannot access $REPO"
gh api "repos/$REPO/actions/secrets" >/dev/null \
  || fail "GitHub credential still lacks Actions Secrets access; OAuth/classic token requires repo scope, fine-grained token requires Secrets(write)"

allow_auto_merge="$(gh api "repos/$REPO" --jq '.allow_auto_merge')"
if [[ "$allow_auto_merge" != true ]]; then
  gh api --method PATCH "repos/$REPO" -F allow_auto_merge=true >/dev/null \
    || fail "GitHub credential cannot enable repository auto-merge"
fi
[[ "$(gh api "repos/$REPO" --jq '.allow_auto_merge')" == true ]] \
  || fail "GitHub did not persist allow_auto_merge=true"

stage server-network
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

stage staging-user
if ! id "$STAGING_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$STAGING_USER"
fi
home_dir="$(getent passwd "$STAGING_USER" | cut -d: -f6)"
[[ -n "$home_dir" && -d "$home_dir" ]] || fail "staging user home is unavailable"

install -d -m 0700 -o root -g root "$STATE_DIR" "$CREDENTIAL_DIR"
work="$(mktemp -d /tmp/control-center-staging-bootstrap.XXXXXX)"
cleanup() {
  rm -rf -- "$work"
  unset GH_TOKEN GITHUB_TOKEN
}
trap cleanup EXIT
trap on_err ERR

stage credentials
ssh_key="$CREDENTIAL_DIR/id_control_center_staging"
if [[ ! -s "$ssh_key" ]]; then
  rm -f -- "$ssh_key" "$ssh_key.pub"
  ssh-keygen -q -t ed25519 -N '' -C 'control-center-github-actions-staging' -f "$ssh_key"
fi
chmod 0600 "$ssh_key"
if [[ ! -s "$ssh_key.pub" ]]; then
  ssh-keygen -y -f "$ssh_key" > "$work/key-body"
  printf 'ssh-ed25519 %s control-center-github-actions-staging\n' "$(awk '{print $2}' "$work/key-body")" > "$ssh_key.pub"
fi
chmod 0644 "$ssh_key.pub"

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

signing_key="$CREDENTIAL_DIR/staging-signing-private.pem"
if [[ ! -s "$signing_key" ]]; then
  openssl genpkey -algorithm ED25519 -out "$signing_key"
fi
chmod 0600 "$signing_key"
install -d -m 0755 -o root -g root "$(dirname "$STAGING_PUBLIC_KEY")"
openssl pkey -in "$signing_key" -pubout -out "$work/staging-signing-public.pem"
install -m 0644 -o root -g root "$work/staging-signing-public.pem" "$STAGING_PUBLIC_KEY"

stage restricted-updater
cat > "$work/control-center-staging-update" <<WRAPPER
#!/usr/bin/env bash
set -Eeuo pipefail
UPDATER=/usr/local/sbin/control-center-update
PUBLIC_KEY=/etc/control-center/staging-update-public.pem
EXPECTED_OWNER=$(printf '%q' "$STAGING_USER")
if [[ "\${1:-}" == --self-test && \$# -eq 1 ]]; then
  [[ \$EUID -eq 0 && -x "\$UPDATER" && -s "\$PUBLIC_KEY" ]]
  exit
fi
[[ \$EUID -eq 0 ]] || { echo 'staging updater must run as root' >&2; exit 1; }
[[ \$# -eq 2 && "\$1" == --package ]] || { echo 'usage: control-center-staging-update --package PATH' >&2; exit 2; }
package="\$2"
[[ "\$package" =~ ^/tmp/control-center-staging-[0-9a-f]{40}/control-center-staging\\.tar\\.gz$ ]] \
  || { echo 'staging package path rejected' >&2; exit 2; }
[[ -f "\$package" && ! -L "\$package" ]] || { echo 'staging package is invalid' >&2; exit 2; }
resolved="\$(realpath -e -- "\$package")"
[[ "\$resolved" == "\$package" ]] || { echo 'staging package path is not canonical' >&2; exit 2; }
owner="\$(stat -c '%U' -- "\$package")"
[[ "\$owner" == "\$EXPECTED_OWNER" ]] || { echo 'staging package owner rejected' >&2; exit 2; }
exec "\$UPDATER" --package "\$package" --public-key "\$PUBLIC_KEY"
WRAPPER
install -m 0755 -o root -g root "$work/control-center-staging-update" "$STAGING_UPDATER"

sudoers="/etc/sudoers.d/control-center-staging"
printf '%s ALL=(root) NOPASSWD: %s\n' "$STAGING_USER" "$STAGING_UPDATER" > "$work/sudoers"
visudo -cf "$work/sudoers" >/dev/null || fail "generated sudoers rule is invalid"
install -m 0440 -o root -g root "$work/sudoers" "$sudoers"

stage ssh-identity
ssh-keygen -A >/dev/null 2>&1 || true
host_key_pub="/etc/ssh/ssh_host_ed25519_key.pub"
[[ -s "$host_key_pub" ]] || fail "ED25519 SSH host key is unavailable"
host_key_type="$(awk '{print $1}' "$host_key_pub")"
host_key_data="$(awk '{print $2}' "$host_key_pub")"
[[ "$host_key_type" == ssh-ed25519 && -n "$host_key_data" ]] || fail "invalid ED25519 SSH host key"
known_host_name="$STAGING_HOST"
[[ "$SSH_PORT" == 22 ]] || known_host_name="[$STAGING_HOST]:$SSH_PORT"
printf '%s %s %s\n' "$known_host_name" "$host_key_type" "$host_key_data" > "$work/known_hosts"

effective_sshd="$(sshd -T -C "user=$STAGING_USER,host=localhost,addr=127.0.0.1" 2>/dev/null || true)"
deny_users="$(awk '$1=="denyusers" {$1=""; sub(/^ /,""); print}' <<<"$effective_sshd")"
if grep -qw -- "$STAGING_USER" <<<"$deny_users"; then
  fail "sshd DenyUsers excludes $STAGING_USER"
fi
allow_users="$(awk '$1=="allowusers" {$1=""; sub(/^ /,""); print}' <<<"$effective_sshd")"
if [[ -n "$allow_users" ]] && ! grep -qw -- "$STAGING_USER" <<<"$allow_users"; then
  fail "sshd AllowUsers does not include $STAGING_USER"
fi

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

stage github-secrets
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

stage state
python3 - "$STATE_DIR/state.json" "$REPO" "$STAGING_HOST" "$STAGING_USER" "$SSH_PORT" "$key_material" <<'PY'
import hashlib
import json
import sys
from datetime import datetime, timezone
path, repo, host, user, port, key_material = sys.argv[1:]
payload = {
    "schema": 3,
    "configured_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    "repository": repo,
    "staging_host": host,
    "staging_user": user,
    "staging_port": int(port),
    "authorized_key_material_sha256": hashlib.sha256(key_material.encode()).hexdigest(),
    "allow_auto_merge": True,
    "server_pinned_staging_trust": True,
    "credentials_persisted_root_only": True,
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

stage complete
trap - ERR
printf 'STAGING_BOOTSTRAP=PASSED\n'
printf 'BOOTSTRAP_SCHEMA=3\n'
printf 'REPOSITORY=%s\n' "$REPO"
printf 'ALLOW_AUTO_MERGE=true\n'
printf 'STAGING_USER=%s\n' "$STAGING_USER"
printf 'STAGING_PORT=%s\n' "$SSH_PORT"
printf 'STAGING_SECRETS=CONFIGURED\n'
printf 'SERVER_PINNED_STAGING_TRUST=true\n'
printf 'PRIVATE_VALUES=NOT_PRINTED\n'
