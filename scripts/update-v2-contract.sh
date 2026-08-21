#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATER="$ROOT/install/update-v2.sh"
MIGRATION_CONTRACT="$ROOT/scripts/platform-v2-migration-contract.sh"

[[ -f "$UPDATER" ]] || { echo "missing update-v2.sh" >&2; exit 1; }
[[ -f "$MIGRATION_CONTRACT" ]] || { echo "missing platform-v2 migration contract" >&2; exit 1; }
bash -n "$UPDATER"

require() {
  local pattern="$1"
  grep -Fq -- "$pattern" "$UPDATER" || {
    printf 'missing updater-v2 contract: %s\n' "$pattern" >&2
    exit 1
  }
}

require "bootstrap-manifest.json\\nbootstrap-manifest.sig\\nmanifest.json\\nmanifest.sig\\ncontrol-center\\ncontrol-center-privileged-worker"
require '"$CURRENT_BIN" verify-release'
require 'bootstrap_version="$(bootstrap_field version)"'
require '"$stage/control-center" verify-release-v2'
require "--worker"
require '[[ "$target_version" == "$bootstrap_version" ]]'
require '[[ "$target_commit" == "$bootstrap_commit" ]]'
require 'systemctl restart "$WORKER_SERVICE"'
require 'socket_ready'
require 'systemctl restart "$SERVICE"'
require 'main_ready'
require 'rollback_main_ready'
require 'grep -Fq "\\\"version\\\":\\\"$current_version\\\""'
require 'rollback failed to restore previous runtime readiness'
require 'rollback "privileged worker acceptance failed"'
require 'rollback "main runtime acceptance failed"'
require 'atomic_link "$old_target" "$CURRENT_LINK"'
require 'atomic_link "$old_target" "$PREVIOUS_LINK"'

if grep -Eq '(^|[[:space:]])(eval|bash[[:space:]]+-c|sh[[:space:]]+-c)([[:space:]]|$)' "$UPDATER"; then
  echo "updater-v2 contains an arbitrary shell execution primitive" >&2
  exit 1
fi

bash "$MIGRATION_CONTRACT"
printf 'update-v2 contract: PASS\n'
