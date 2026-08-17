#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$SCRIPT_DIR/acceptance.sh"
[[ -r "$SOURCE" ]] || { echo "ACCEPTANCE HOTFIX FAIL: source acceptance.sh missing" >&2; exit 1; }

TMP="$(mktemp "${TMPDIR:-/tmp}/srvcc-acceptance-1.3.0.XXXXXX.sh")"
cleanup() { rm -f -- "$TMP"; }
trap cleanup EXIT

python3 - "$SOURCE" "$TMP" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1])
target = Path(sys.argv[2])
text = source.read_text(encoding="utf-8")

cache_needle = '    [[ -s "$restored_conf" && -s "$restored_sam" ]] || fail "isolated restored domain is incomplete"\n'
cache_insert = cache_needle + '    mkdir -p -- "$restored/cache"\n'

if '    mkdir -p -- "$restored/cache"\n' in text:
    patched = text
elif cache_needle in text:
    patched = text.replace(cache_needle, cache_insert, 1)
else:
    raise SystemExit("acceptance cache hotfix anchor not found; refusing unsafe patch")

sid_needle = '''    restored_sid="$(ldbsearch -H "$restored_sam" -b '' -s base objectSid 2>/dev/null | awk '/^objectSid: /{print $2; exit}')"\n    [[ "$restored_sid" == "$live_sid" ]] || fail "restored domain SID mismatch"\n'''
sid_replace = '''    restored_base_dn="$(ldbsearch -H "$restored_sam" -b '' -s base defaultNamingContext 2>/dev/null | awk -F': ' '/^defaultNamingContext: /{print $2; exit}')"\n    [[ -n "$restored_base_dn" ]] || fail "restored domain naming context missing"\n    restored_sid="$(ldbsearch -H "$restored_sam" -b "$restored_base_dn" -s base objectSid 2>/dev/null | awk '/^objectSid: /{print $2; exit}')"\n    [[ -n "$restored_sid" ]] || fail "restored domain SID missing"\n    [[ "$restored_sid" == "$live_sid" ]] || fail "restored domain SID mismatch"\n'''

if '    restored_base_dn="$(ldbsearch -H "$restored_sam" -b \'\' -s base defaultNamingContext' in patched:
    pass
elif sid_needle in patched:
    patched = patched.replace(sid_needle, sid_replace, 1)
else:
    raise SystemExit("acceptance SID hotfix anchor not found; refusing unsafe patch")

target.write_text(patched, encoding="utf-8")
PY

chmod 0700 "$TMP"
set +e
bash "$TMP" "$@"
rc=$?
set -e
exit "$rc"
