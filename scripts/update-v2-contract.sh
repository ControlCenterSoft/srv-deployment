#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATER="$ROOT/install/update-v2.sh"

[[ -f "$UPDATER" ]] || { echo "missing update-v2.sh" >&2; exit 1; }
bash -n "$UPDATER"

require() {
  local pattern="$1"
  grep -Fq -- "$pattern" "$UPDATER" || {
    printf 'missing updater-v2 contract: %s\n' "$pattern" >&2
    exit 1
  }
}

require "manifest.json\\nmanifest.sig\\ncontrol-center\\ncontrol-center-privileged-worker"
require "verify-release-v2"
require "--worker"
require 'systemctl restart "$WORKER_SERVICE"'
require 'socket_ready'
require 'systemctl restart "$SERVICE"'
require 'main_ready'
require 'rollback "privileged worker acceptance failed"'
require 'rollback "main runtime acceptance failed"'
require 'atomic_link "$old_target" "$CURRENT_LINK"'
require 'atomic_link "$old_target" "$PREVIOUS_LINK"'

if grep -Eq '(^|[[:space:]])(eval|bash[[:space:]]+-c|sh[[:space:]]+-c)([[:space:]]|$)' "$UPDATER"; then
  echo "updater-v2 contains an arbitrary shell execution primitive" >&2
  exit 1
fi

printf 'update-v2 contract: PASS\n'
