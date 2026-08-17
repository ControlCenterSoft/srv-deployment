#!/usr/bin/env bash
set -Eeuo pipefail

RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE="${RELEASE_DIR}/apply.sh"
TMP="$(mktemp "${RELEASE_DIR}/.apply-1.3.1.XXXXXX.sh")"
cleanup() { rm -f -- "$TMP"; }
trap cleanup EXIT

python3 - "$SOURCE" "$TMP" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1])
target = Path(sys.argv[2])
text = source.read_text(encoding="utf-8")
if 'RELEASE_ID="1.3.0"' not in text or 'RELEASE_VERSION="1.3.0"' not in text:
    raise SystemExit("apply 1.3.1 release anchors missing")
text = text.replace("1.3.0", "1.3.1")
target.write_text(text, encoding="utf-8")
PY

chmod 0700 "$TMP"
bash "$TMP" "$@"
