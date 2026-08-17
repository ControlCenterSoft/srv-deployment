#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
CONFIG="${REPO_ROOT}/deployment.json"
STATE_ROOT="/var/lib/srv-deployment"
RUN_ROOT="${STATE_ROOT}/runs"
STATUS_FILE="${STATE_ROOT}/last-result.env"
LOCK_FILE="${STATE_ROOT}/deploy.lock"

log() {
    printf '%s %s\n' "$(date -Is)" "$*"
}

fail() {
    log "DEPLOY FAIL: $*" >&2
    exit 1
}

write_status() {
    local result="$1"
    local stage="$2"
    local release_id="$3"
    local tmp

    install -d -m 0750 "$STATE_ROOT"
    tmp="$(mktemp "${STATUS_FILE}.tmp.XXXXXX")"
    {
        printf 'result=%s\n' "$result"
        printf 'stage=%s\n' "$stage"
        printf 'release_id=%s\n' "$release_id"
        printf 'remote_sha=%s\n' "$REMOTE_SHA"
        printf 'finished_at=%s\n' "$(date -Is)"
        printf 'project=%s\n' "$PROJECT"
    } > "$tmp"
    chmod 0640 "$tmp"
    mv -f "$tmp" "$STATUS_FILE"
}

[[ "$(id -u)" -eq 0 ]] || fail "must run as root"
[[ -f "$CONFIG" ]] || fail "deployment config is missing: $CONFIG"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"

install -d -m 0750 "$STATE_ROOT" "$RUN_ROOT"
exec 9>"$LOCK_FILE"
if command -v flock >/dev/null 2>&1; then
    if ! flock -n 9; then
        log "DEPLOY SKIP: another deployment is already running"
        exit 0
    fi
fi

metadata="$(python3 - "$CONFIG" "$REPO_ROOT" <<'PY'
import hashlib
import json
import pathlib
import re
import sys

config_path = pathlib.Path(sys.argv[1]).resolve()
root = pathlib.Path(sys.argv[2]).resolve()


def die(message: str) -> None:
    raise SystemExit(f"deployment metadata error: {message}")


def resolve_repo_path(value: object, field: str) -> pathlib.Path:
    if not isinstance(value, str) or not value or "\n" in value or "\r" in value:
        die(f"invalid {field}")
    candidate = (root / value).resolve()
    if candidate != root and root not in candidate.parents:
        die(f"{field} escapes repository root")
    return candidate

with config_path.open("r", encoding="utf-8") as handle:
    config = json.load(handle)

if config.get("schema_version") != 1:
    die("unsupported deployment schema_version")

if config.get("enabled") is not True:
    print("DISABLED")
    raise SystemExit(0)

release_id = config.get("release_id") or config.get("release")
if not isinstance(release_id, str) or not re.fullmatch(r"[A-Za-z0-9._-]+", release_id):
    die("invalid release_id")

release_dir = resolve_repo_path(config.get("release_path"), "release_path")
manifest_path = resolve_repo_path(config.get("manifest"), "manifest")
if manifest_path.parent != release_dir:
    die("manifest is outside release_path")
if not manifest_path.is_file():
    die("manifest file is missing")

with manifest_path.open("r", encoding="utf-8") as handle:
    manifest = json.load(handle)

if manifest.get("schema_version") != 1:
    die("unsupported manifest schema_version")
if manifest.get("release_id") != release_id:
    die("manifest release_id mismatch")

scripts = manifest.get("scripts")
if not isinstance(scripts, dict):
    die("manifest scripts section is missing")

resolved = {}
for stage in ("preflight", "apply", "acceptance", "rollback"):
    configured = resolve_repo_path(config.get(stage), stage)
    entry = scripts.get(stage)
    if not isinstance(entry, dict):
        die(f"manifest entry is missing for {stage}")
    rel = entry.get("path")
    expected_hash = entry.get("sha256")
    if not isinstance(rel, str) or not rel or pathlib.PurePosixPath(rel).is_absolute() or ".." in pathlib.PurePosixPath(rel).parts:
        die(f"invalid manifest path for {stage}")
    expected = (release_dir / rel).resolve()
    if expected != configured:
        die(f"configured {stage} does not match manifest")
    if not configured.is_file():
        die(f"script is missing: {stage}")
    if not isinstance(expected_hash, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", expected_hash):
        die(f"invalid sha256 for {stage}")
    actual_hash = hashlib.sha256(configured.read_bytes()).hexdigest()
    if actual_hash.lower() != expected_hash.lower():
        die(f"sha256 mismatch for {stage}")
    resolved[stage] = configured

print("ENABLED")
print(release_id)
for stage in ("preflight", "apply", "acceptance", "rollback"):
    print(resolved[stage])
PY
)" || fail "deployment metadata validation failed"

mapfile -t meta <<< "$metadata"
if [[ "${meta[0]:-}" == "DISABLED" ]]; then
    write_status "skipped" "disabled" "none"
    log "DEPLOY SKIP: deployment.json is disabled"
    exit 0
fi

[[ "${#meta[@]}" -eq 6 && "${meta[0]}" == "ENABLED" ]] || fail "unexpected deployment metadata output"
RELEASE_ID="${meta[1]}"
PREFLIGHT="${meta[2]}"
APPLY="${meta[3]}"
ACCEPTANCE="${meta[4]}"
ROLLBACK="${meta[5]}"

RUN_ID="$(date +%Y%m%dT%H%M%S)-${REMOTE_SHA:0:12}-${RELEASE_ID}"
RUN_LOG="${RUN_ROOT}/${RUN_ID}.log"
exec > >(tee -a "$RUN_LOG") 2>&1

log "DEPLOY START: release=${RELEASE_ID} sha=${REMOTE_SHA} project=${PROJECT}"

if ! bash "$PREFLIGHT" "$PROJECT" "$REMOTE_SHA"; then
    write_status "failed" "preflight" "$RELEASE_ID"
    fail "preflight failed for ${RELEASE_ID}"
fi

if ! bash "$APPLY" "$PROJECT" "$REMOTE_SHA"; then
    log "DEPLOY WARN: apply failed; attempting rollback"
    bash "$ROLLBACK" "$PROJECT" "$REMOTE_SHA" || log "DEPLOY WARN: rollback also failed"
    write_status "failed" "apply" "$RELEASE_ID"
    fail "apply failed for ${RELEASE_ID}"
fi

if ! bash "$ACCEPTANCE" "$PROJECT" "$REMOTE_SHA"; then
    log "DEPLOY WARN: acceptance failed; attempting rollback"
    bash "$ROLLBACK" "$PROJECT" "$REMOTE_SHA" || log "DEPLOY WARN: rollback also failed"
    write_status "failed" "acceptance" "$RELEASE_ID"
    fail "acceptance failed for ${RELEASE_ID}"
fi

write_status "success" "acceptance" "$RELEASE_ID"
log "DEPLOY PASS: release=${RELEASE_ID} sha=${REMOTE_SHA}"
