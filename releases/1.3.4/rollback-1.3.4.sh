#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../1.3.3" && pwd -P)"
bash "${SOURCE_DIR}/rollback-1.3.3.sh" "$@"
printf 'ROLLBACK 1.3.4 PASS: delegated to frozen 1.3.3 rollback transaction\n'
