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
apt-get install -y --no-install-recommends ca-certificates git

tmp_root="$(mktemp -d /tmp/srv-control-installer.XXXXXX)"
trap 'rm -rf "$tmp_root"' EXIT

git clone --depth 1 --branch main "$REPO_URL" "$tmp_root/repo"
repo_root="$tmp_root/repo"

[[ -x "$repo_root/installer/install.sh" ]] \
    || fail "installer/install.sh is missing"
[[ -s "$repo_root/deployment.json" ]] \
    || fail "deployment.json is missing"

printf 'INSTALL BOOTSTRAP: source=%s\n' "$REPO_URL"
bash "$repo_root/installer/install.sh" "$@"
