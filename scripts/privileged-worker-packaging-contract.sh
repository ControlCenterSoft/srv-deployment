#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$ROOT/install/install.sh"
UNINSTALL="$ROOT/install/uninstall.sh"
UNIT="$ROOT/packaging/systemd/control-center-privileged-worker.service"
BUILD="$ROOT/scripts/build.sh"

fail() {
  printf 'privileged-worker packaging contract failed: %s\n' "$*" >&2
  exit 1
}
require_literal() {
  local file="$1" literal="$2"
  grep -Fq -- "$literal" "$file" || fail "$file is missing: $literal"
}

for file in "$INSTALL" "$UNINSTALL" "$UNIT" "$BUILD"; do
  [[ -f "$file" ]] || fail "missing $file"
done

require_literal "$BUILD" 'dist/control-center-privileged-worker-linux-amd64'
require_literal "$BUILD" 'dist/control-center-privileged-worker-linux-arm64'
require_literal "$INSTALL" 'CONTROL_CENTER_PRIVILEGED_WORKER_BINARY'
require_literal "$INSTALL" 'control-center-privileged-worker-linux-$artifact_arch'
require_literal "$INSTALL" 'install -m 0555 "$worker_binary" "$tmp_release/control-center-privileged-worker"'
require_literal "$INSTALL" 'packaging/systemd/control-center-privileged-worker.service'
require_literal "$INSTALL" 'systemctl enable control-center-privileged-worker.service control-center.service'
require_literal "$INSTALL" 'systemctl restart control-center-privileged-worker.service'
require_literal "$INSTALL" '[[ -S /run/control-center/privileged-worker.sock ]]'
require_literal "$INSTALL" 'root:control-center:660'
require_literal "$INSTALL" 'worker_was_enabled'
require_literal "$INSTALL" 'worker_was_active'
require_literal "$UNINSTALL" 'systemctl disable --now control-center-privileged-worker.service'
require_literal "$UNINSTALL" '/etc/systemd/system/control-center-privileged-worker.service'
require_literal "$UNINSTALL" '/var/log/control-center-privileged'
require_literal "$UNIT" 'User=root'
require_literal "$UNIT" 'Group=control-center'
require_literal "$UNIT" 'ExecStart=/usr/local/lib/control-center/current/control-center-privileged-worker'
require_literal "$UNIT" 'CapabilityBoundingSet='
require_literal "$UNIT" 'RestrictAddressFamilies=AF_UNIX'

printf 'privileged-worker packaging contract: PASS\n'
