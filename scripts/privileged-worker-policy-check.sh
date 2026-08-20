#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORKER="$ROOT/packaging/systemd/control-center-privileged.service"
WEB="$ROOT/packaging/systemd/control-center.service"
[[ -f "$WORKER" && -f "$WEB" ]]
grep -Fxq 'User=root' "$WORKER"
grep -Fxq 'Group=control-center' "$WORKER"
grep -Fxq 'NoNewPrivileges=yes' "$WORKER"
grep -Fxq 'CapabilityBoundingSet=' "$WORKER"
grep -Fxq 'AmbientCapabilities=' "$WORKER"
grep -Fxq 'RestrictAddressFamilies=AF_UNIX' "$WORKER"
grep -Fxq 'EnvironmentFile=-/etc/control-center/privileged.env' "$WORKER"
grep -Fxq 'User=control-center' "$WEB"
grep -Fxq 'NoNewPrivileges=yes' "$WEB"
grep -Fxq 'CapabilityBoundingSet=' "$WEB"
if grep -Eq '(/bin/(ba)?sh|[[:space:]]-c[[:space:]])' "$WORKER"; then
  echo 'ERROR: shell execution found in privileged worker unit' >&2
  exit 1
fi
printf 'PRIVILEGED_POLICY_CHECK=PASSED\n'
