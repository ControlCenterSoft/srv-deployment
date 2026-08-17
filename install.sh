#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="https://github.com/filosoff31/srv-deployment.git"

fail() {
    printf 'INSTALL BOOTSTRAP FAIL: %s\n' "$*" >&2
    exit 1
}

[[ "$(id -u)" -eq 0 ]] || fail "run as root: sudo bash install.sh"
command -v apt-get >/dev/null 2>&1 \
    || fail "this installer currently supports Debian/Ubuntu systems with apt-get"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
    ca-certificates \
    git

tmp_root="$(mktemp -d /tmp/srv-control-installer.XXXXXX)"
trap 'rm -rf "$tmp_root"' EXIT

git clone \
    --depth 1 \
    --branch main \
    "$REPO_URL" \
    "$tmp_root/repo"

repo_root="$tmp_root/repo"

release_id="$(
    sed -n 's/^[[:space:]]*"release_id":[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$repo_root/deployment.json" \
        | head -n 1
)"

release_path="$(
    sed -n 's/^[[:space:]]*"release_path":[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$repo_root/deployment.json" \
        | head -n 1
)"

[[ -n "$release_id" ]] || fail "cannot resolve active release_id"
[[ -n "$release_path" ]] || fail "cannot resolve active release_path"
[[ -f "$repo_root/$release_path/manifest.json" ]] \
    || fail "active release manifest is missing"

release_version="$(
    sed -n 's/^[[:space:]]*"release_version":[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$repo_root/$release_path/manifest.json" \
        | head -n 1
)"

[[ -n "$release_version" ]] || fail "cannot resolve active release_version"

runner="$repo_root/installer/.install-current.sh"

sed -E \
    -e "s|^RELEASE_ID=.*$|RELEASE_ID=\"${release_id}\"|" \
    -e "s|^RELEASE_VERSION=.*$|RELEASE_VERSION=\"${release_version}\"|" \
    "$repo_root/installer/install.sh" > "$runner"

chmod 0755 "$runner"

printf 'INSTALL BOOTSTRAP: release=%s version=%s\n' \
    "$release_id" \
    "$release_version"

bash "$runner" "$@"

if [[ -x "$repo_root/installer/install-system-admin.sh" ]]; then
    bash "$repo_root/installer/install-system-admin.sh"
fi
