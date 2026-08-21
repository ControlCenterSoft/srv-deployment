#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$ROOT/install/install.sh"
UPDATER="$ROOT/install/update-v2.sh"
MIGRATE="$ROOT/install/migrate-platform-v2.sh"
UNIT="$ROOT/packaging/systemd/control-center-privileged-worker.service"

fail() {
  printf 'platform-v2 migration contract failed: %s\n' "$*" >&2
  exit 1
}
require_literal() {
  local file="$1" literal="$2"
  grep -Fq -- "$literal" "$file" || fail "$file is missing: $literal"
}

for file in "$INSTALL" "$UPDATER" "$MIGRATE" "$UNIT"; do
  [[ -f "$file" ]] || fail "missing $file"
done

bash -n "$INSTALL"
bash -n "$UPDATER"
bash -n "$MIGRATE"

# Clean 1.1.x installs must persist the dual-runtime updater, not the legacy
# schema-1 updater retained only for the frozen 1.0.0 compatibility baseline.
require_literal "$INSTALL" '[[ -f "$REPO_ROOT/install/update-v2.sh" ]] || die "update-v2 script is missing"'
require_literal "$INSTALL" 'install -m 0755 "$REPO_ROOT/install/update-v2.sh" "$UPDATE_SCRIPT"'

# The migration bootstrap is deliberately narrow: it may install only the
# privileged-worker platform unit and only while an accepted 1.0.0 runtime is
# still the active release. It must not switch release pointers or execute a
# candidate binary.
require_literal "$MIGRATE" 'EXPECTED_CURRENT_VERSION="${CONTROL_CENTER_EXPECTED_MIGRATION_FROM:-1.0.0}"'
require_literal "$MIGRATE" '[[ "$current_version" == "$EXPECTED_CURRENT_VERSION" ]]'
require_literal "$MIGRATE" '[[ -L "$CURRENT_LINK" ]]'
require_literal "$MIGRATE" '[[ -x "$CURRENT_BIN" ]]'
require_literal "$MIGRATE" 'install -D -o root -g root -m 0644 "$UNIT_SOURCE" "$WORKER_UNIT_PATH"'
require_literal "$MIGRATE" 'systemctl daemon-reload'
require_literal "$MIGRATE" 'systemctl cat "$WORKER_SERVICE" >/dev/null 2>&1'
require_literal "$MIGRATE" 'systemctl is-active --quiet "$WORKER_SERVICE"'
require_literal "$MIGRATE" 'migration completed; worker unit installed but intentionally not started before signed dual-runtime switch'

for forbidden in \
  'systemctl start "$WORKER_SERVICE"' \
  'systemctl restart "$WORKER_SERVICE"' \
  'systemctl enable "$WORKER_SERVICE"' \
  'control-center-privileged-worker.sock'; do
  if grep -Fq -- "$forbidden" "$MIGRATE"; then
    fail "migration bootstrap contains forbidden pre-update activation: $forbidden"
  fi
done

for file in "$UPDATER" "$MIGRATE"; do
  if grep -Eq '(^|[[:space:]])(eval|bash[[:space:]]+-c|sh[[:space:]]+-c)([[:space:]]|$)' "$file"; then
    fail "$file contains an arbitrary shell execution primitive"
  fi
done

printf 'platform-v2 migration contract: PASS\n'
