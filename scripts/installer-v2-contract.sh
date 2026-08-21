#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT/install/install.sh"
UPDATER_V2="$ROOT/install/update-v2.sh"
LEGACY_UPDATER="$ROOT/install/update.sh"

fail() {
  printf 'installer-v2 contract failed: %s\n' "$*" >&2
  exit 1
}
require_literal() {
  local literal="$1"
  grep -Fq -- "$literal" "$INSTALLER" || fail "installer is missing: $literal"
}

[[ -f "$INSTALLER" ]] || fail "install.sh is missing"
[[ -f "$UPDATER_V2" ]] || fail "update-v2.sh is missing"
[[ -f "$LEGACY_UPDATER" ]] || fail "legacy update.sh baseline is missing"
bash -n "$INSTALLER"
bash -n "$UPDATER_V2"

require_literal '[[ -f "$REPO_ROOT/install/update-v2.sh" ]] || die "update-v2 script is missing"'
require_literal 'install -m 0755 "$REPO_ROOT/install/update-v2.sh" "$UPDATE_SCRIPT"'
require_literal 'if [[ -f "$UPDATE_SCRIPT" ]]; then cp -a -- "$UPDATE_SCRIPT" "$backup/update"; had_update=1; fi'
require_literal '(( had_update )) && install -D -m 0755 "$backup/update" "$UPDATE_SCRIPT" || rm -f -- "$UPDATE_SCRIPT"'

if grep -Fq -- 'install -m 0755 "$REPO_ROOT/install/update.sh" "$UPDATE_SCRIPT"' "$INSTALLER"; then
  fail "1.1.x installer still selects legacy schema-1 updater"
fi
if grep -Fq -- '[[ -f "$REPO_ROOT/install/update.sh" ]] || die "update script is missing"' "$INSTALLER"; then
  fail "1.1.x installer still requires legacy updater as active implementation"
fi

printf 'installer-v2 contract: PASS\n'
