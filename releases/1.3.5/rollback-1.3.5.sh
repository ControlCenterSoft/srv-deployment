#!/usr/bin/env bash
set -Eeuo pipefail
SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${SOURCE_DIR}/rollback-1.3.4.sh" "$@"
printf 'ROLLBACK 1.3.5 PASS: delegated to proven 1.3.4/1.3.3 rollback transaction\n'
