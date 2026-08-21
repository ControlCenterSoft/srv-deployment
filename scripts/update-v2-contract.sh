#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATER="$ROOT/install/update-v2.sh"
MIGRATION_CONTRACT="$ROOT/scripts/platform-v2-migration-contract.sh"
ACCEPTANCE="$ROOT/.github/workflows/acceptance-1.1.yml"
UPDATE_ACCEPTANCE="$ROOT/scripts/update-acceptance.sh"
STAGING_DEPLOY="$ROOT/scripts/staging-deploy.sh"

[[ -f "$UPDATER" ]] || { echo "missing update-v2.sh" >&2; exit 1; }
[[ -f "$MIGRATION_CONTRACT" ]] || { echo "missing platform-v2 migration contract" >&2; exit 1; }
[[ -f "$ACCEPTANCE" ]] || { echo "missing acceptance-1.1.yml" >&2; exit 1; }
[[ -f "$UPDATE_ACCEPTANCE" ]] || { echo "missing update-acceptance.sh" >&2; exit 1; }
[[ -f "$STAGING_DEPLOY" ]] || { echo "missing staging-deploy.sh" >&2; exit 1; }
bash -n "$UPDATER" "$UPDATE_ACCEPTANCE" "$STAGING_DEPLOY"

require() {
  local pattern="$1"
  grep -Fq -- "$pattern" "$UPDATER" || {
    printf 'missing updater-v2 contract: %s\n' "$pattern" >&2
    exit 1
  }
}

require_file() {
  local file="$1" label="$2" pattern="$3"
  grep -Fq -- "$pattern" "$file" || {
    printf 'missing %s contract: %s\n' "$label" "$pattern" >&2
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
require 'CURRENT_WORKER="$CURRENT_LINK/control-center-privileged-worker"'
require 'current_commit="$("$CURRENT_BIN" build-info --field commit)"'
require 'if (( comparison == 0 && ! ALLOW_DOWNGRADE )); then'
require '[[ "$current_commit" == "$target_commit" ]]'
require 'cmp -s -- "$stage/control-center" "$CURRENT_BIN"'
require 'cmp -s -- "$stage/control-center-privileged-worker" "$CURRENT_WORKER"'
require 'already active with exact signed identity; no update required'
require 'if (( comparison > 0 && ! ALLOW_DOWNGRADE )); then'
require 'is older than current'
require 'systemctl enable "$WORKER_SERVICE"'
require 'rollback "privileged worker enable failed"'
require 'systemctl restart "$WORKER_SERVICE"'
require 'socket_ready'
require 'systemctl restart "$SERVICE"'
require 'main_ready'
require 'rollback_main_ready'
require 'current_version'
require 'worker_restore_failed'
require 'main_restore_failed'
require 'rollback failed to restore previous runtime readiness'
require 'rollback failed to restore main service policy'
require 'rollback failed to restore privileged worker policy'
require 'rollback "privileged worker acceptance failed"'
require 'rollback "main runtime acceptance failed"'
require 'atomic_link "$old_target" "$CURRENT_LINK"'
require 'atomic_link "$old_target" "$PREVIOUS_LINK"'

# Full Acceptance must exercise the same dual-runtime trust/update path that RC
# staging will use. These textual gates deliberately fail if staging regresses
# to the legacy schema-1 package or stops asserting the privileged worker.
require_file "$ACCEPTANCE" "Full Acceptance" 'go run ./cmd/release-tool package-v2'
require_file "$ACCEPTANCE" "Full Acceptance" '--worker dist/control-center-privileged-worker-linux-amd64'
require_file "$ACCEPTANCE" "Full Acceptance" 'control-center-privileged-worker-linux-amd64 ./cmd/control-center-privileged-worker'
require_file "$ACCEPTANCE" "Full Acceptance" "expected_entries=\$'bootstrap-manifest.json\\nbootstrap-manifest.sig\\nmanifest.json\\nmanifest.sig\\ncontrol-center\\ncontrol-center-privileged-worker'"
require_file "$ACCEPTANCE" "Full Acceptance" "systemctl is-active --quiet control-center-privileged-worker.service"
require_file "$ACCEPTANCE" "Full Acceptance" "systemctl is-enabled --quiet control-center-privileged-worker.service"
require_file "$ACCEPTANCE" "Full Acceptance" "root:control-center:660"

# The lifecycle acceptance invoked after clean install must itself produce and
# attack package-v2. A schema-1 test here would fail against the installed v2
# updater and, worse, would stop exercising worker-first rollback semantics.
require_file "$UPDATE_ACCEPTANCE" "update-v2 acceptance" 'go run ./cmd/release-tool package-v2'
require_file "$UPDATE_ACCEPTANCE" "update-v2 acceptance" '--worker "$worker"'
require_file "$UPDATE_ACCEPTANCE" "update-v2 acceptance" './cmd/control-center-privileged-worker'
require_file "$UPDATE_ACCEPTANCE" "update-v2 acceptance" "V2_ENTRIES=\$'bootstrap-manifest.json\\nbootstrap-manifest.sig\\nmanifest.json\\nmanifest.sig\\ncontrol-center\\ncontrol-center-privileged-worker'"
require_file "$UPDATE_ACCEPTANCE" "update-v2 acceptance" 'unverified-candidate-executed'
require_file "$UPDATE_ACCEPTANCE" "update-v2 acceptance" 'tampered schema-2 manifest was accepted'
require_file "$UPDATE_ACCEPTANCE" "update-v2 acceptance" 'worker-broken'
require_file "$UPDATE_ACCEPTANCE" "update-v2 acceptance" 'assert_worker_ready'
require_file "$UPDATE_ACCEPTANCE" "update-v2 acceptance" 'root:control-center:660'

require_file "$STAGING_DEPLOY" "real staging" "systemctl is-active --quiet control-center-privileged-worker.service"
require_file "$STAGING_DEPLOY" "real staging" "systemctl is-enabled --quiet control-center-privileged-worker.service"
require_file "$STAGING_DEPLOY" "real staging" "root:control-center:660"

for file in "$UPDATER" "$UPDATE_ACCEPTANCE"; do
  if grep -Eq '(^|[[:space:]])(eval|bash[[:space:]]+-c|sh[[:space:]]+-c)([[:space:]]|$)' "$file"; then
    echo "arbitrary shell execution primitive detected in $(basename "$file")" >&2
    exit 1
  fi
done

bash "$MIGRATION_CONTRACT"
printf 'update-v2 contract: PASS\n'
