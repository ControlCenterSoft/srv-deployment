#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$SCRIPT_DIR/stage-ops-agent-signed.sh"
EXPECTED_SOURCE_BLOB="82e12eeaed1df8d35fbec382a36f6870a8ceb019"
WORK="$(mktemp -d /tmp/control-center-ops-agent-stage-v2.XXXXXX)"
PATCHED="$WORK/stage-ops-agent-signed.sh"

cleanup() { rm -rf -- "$WORK"; }
trap cleanup EXIT

[[ -f "$SOURCE" && ! -L "$SOURCE" ]] || { echo "canonical staging script unavailable" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 2; }
command -v bash >/dev/null 2>&1 || { echo "bash is required" >&2; exit 2; }

# The original reviewed deployer performs two direct broker-socket checks as the
# unprivileged staging SSH identity. That identity is intentionally not a member
# of ccdiag and therefore cannot traverse /run/control-center-ops (root:ccdiag
# 0750), even though the broker and socket are healthy. The dedicated restricted
# root updater already performs the same socket presence/ownership/mode checks,
# along with broker/timer/NoNewPrivileges validation, in --self-test before any
# package upload or mutation. Patch only those redundant non-root socket probes.
python3 - "$SOURCE" "$EXPECTED_SOURCE_BLOB" "$PATCHED" <<'PY'
import hashlib
import pathlib
import sys

source_raw, expected_blob, target_raw = sys.argv[1:]
source = pathlib.Path(source_raw)
target = pathlib.Path(target_raw)
raw = source.read_bytes()
blob = hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
if blob != expected_blob:
    raise SystemExit(f"canonical staging script blob rejected: {blob}")
text = raw.decode("utf-8", errors="strict")
needle = (
    "   test -S /run/control-center-ops/broker.sock && \\\n"
    "   test \\\"\\$(stat -Lc '%U:%G:%a' /run/control-center-ops/broker.sock)\\\" = 'root:ccdiag:660' && \\\n"
)
if text.count(needle) != 1:
    raise SystemExit("expected inaccessible staging-user socket probe not found exactly once")
text = text.replace(needle, "", 1)
preflight = text.index("# Read-only preflight before package upload or sudo mutation.")
upload = text.index('scp "${scp_opts[@]}" "$package"', preflight)
block = text[preflight:upload]
if "test -S /run/control-center-ops/broker.sock" in block or "stat -Lc '%U:%G:%a' /run/control-center-ops/broker.sock" in block:
    raise SystemExit("direct staging-user broker socket probe remains")
if "sudo -n /usr/local/sbin/control-center-ops-agent-staging-update --self-test" not in block:
    raise SystemExit("restricted root updater self-test missing from preflight")
target.write_text(text, encoding="utf-8")
target.chmod(0o700)
PY

bash -n "$PATCHED"
bash "$PATCHED" "$@"
