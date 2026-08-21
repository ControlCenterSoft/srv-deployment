#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
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

for file in "$UPDATER" "$MIGRATE" "$UNIT"; do
  [[ -f "$file" ]] || fail "missing $file"
done

bash -n "$UPDATER"
bash -n "$MIGRATE"

# The migration bootstrap is deliberately narrow: it may install only the
# privileged-worker platform unit and only while the exact accepted 1.0.0
# runtime is still the active release. It must not switch release pointers or
# execute a candidate binary.
require_literal "$MIGRATE" 'EXPECTED_CURRENT_VERSION="${CONTROL_CENTER_EXPECTED_MIGRATION_FROM:-1.0.0}"'
require_literal "$MIGRATE" 'EXPECTED_CURRENT_COMMIT="${CONTROL_CENTER_EXPECTED_MIGRATION_COMMIT:-1b364ae88789696bf98537d21544de8a259d086d}"'
require_literal "$MIGRATE" '[[ "$current_version" == "$EXPECTED_CURRENT_VERSION" ]]'
require_literal "$MIGRATE" '[[ "$current_commit" == "$EXPECTED_CURRENT_COMMIT" ]]'
require_literal "$MIGRATE" '[[ -L "$CURRENT_LINK" ]]'
require_literal "$MIGRATE" '[[ -x "$CURRENT_BIN" ]]'
require_literal "$MIGRATE" 'install -D -o root -g root -m 0644 "$UNIT_SOURCE" "$WORKER_UNIT_PATH"'
require_literal "$MIGRATE" 'systemctl daemon-reload'
require_literal "$MIGRATE" 'systemctl cat "$WORKER_SERVICE" >/dev/null 2>&1'
require_literal "$MIGRATE" 'systemctl is-active --quiet "$WORKER_SERVICE"'
require_literal "$MIGRATE" 'systemctl is-enabled --quiet "$WORKER_SERVICE"'
require_literal "$MIGRATE" 'migration completed; worker unit installed but intentionally not started before signed dual-runtime switch'
require_literal "$MIGRATE" 'WORKER_ACTIVATED=false'

# Embedded unit must retain the same security-critical boundary as the
# canonical packaging unit. This catches drift even though the migration is
# intentionally self-contained for hosts without a repository checkout.
for literal in \
  'ExecStart=/usr/local/lib/control-center/current/control-center-privileged-worker' \
  'NoNewPrivileges=yes' \
  'CapabilityBoundingSet=' \
  'AmbientCapabilities=' \
  'RestrictAddressFamilies=AF_UNIX' \
  'ProtectSystem=strict' \
  'MemoryDenyWriteExecute=yes'; do
  require_literal "$MIGRATE" "$literal"
  require_literal "$UNIT" "$literal"
done

for forbidden in \
  'systemctl start "$WORKER_SERVICE"' \
  'systemctl restart "$WORKER_SERVICE"' \
  'systemctl enable "$WORKER_SERVICE"'; do
  if grep -Fq -- "$forbidden" "$MIGRATE"; then
    fail "migration bootstrap contains forbidden pre-update activation: $forbidden"
  fi
done

if grep -Fq -- 'atomic_link ' "$MIGRATE"; then
  fail "migration bootstrap must not switch release pointers"
fi

for file in "$UPDATER" "$MIGRATE"; do
  if grep -Eq '(^|[[:space:]])(eval|bash[[:space:]]+-c|sh[[:space:]]+-c)([[:space:]]|$)' "$file"; then
    fail "$file contains an arbitrary shell execution primitive"
  fi
done

printf 'platform-v2 migration contract: PASS\n'
