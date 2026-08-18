#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

REPO_URL="${SRVCC_REPO_URL:-https://github.com/filosoff31/srv-deployment.git}"
PROJECT="${1:-/opt/srv-control}"
EXPECTED_RELEASE="2.0.0"
EXPECTED_INTERVAL=5
STATE_PUBLISHER="/usr/local/sbin/srvcc-github-agent.state-publisher"
CONFIGURATOR="/usr/local/sbin/srvcc-configure-auto-updates"
TMP_ROOT="$(mktemp -d /var/tmp/control-center-2.0-bootstrap.XXXXXX)"

OBSOLETE_UNPUBLISHED_BRANCHES=(
    feature/1.3.0-github-update-timestamps
    hotfix/1.3.0-external-share-editing
    hotfix/1.3.0-external-share-editing-final
    hotfix/1.3.0-external-share-editing-pr-placeholder
    hotfix/1.3.0-samba-domain-performance
    hotfix/1.3.0-samba-monitor-sandbox
    hotfix/1.3.0-samba-sid
    hotfix/1.3.0-share-create
    hotfix/1.3.0-share-create-external-path
    hotfix/1.3.0-state-repository
    release/1.4.0
)

log(){ printf '%s %s\n' "$(date -Is)" "$*"; }
fail(){ log "BOOTSTRAP FAIL: $*" >&2; exit 1; }
cleanup(){ rm -rf -- "$TMP_ROOT"; }
trap cleanup EXIT

[[ "$(id -u)" -eq 0 ]] || fail "must run as root"
for cmd in git python3 systemctl; do
    command -v "$cmd" >/dev/null 2>&1 || fail "$cmd is required"
done
[[ -d "$PROJECT" ]] || fail "Control Center project path is missing: $PROJECT"

log "Cloning current production repository"
git clone --quiet --depth 1 --single-branch --branch main "$REPO_URL" "$TMP_ROOT/repo"
REMOTE_SHA="$(git -C "$TMP_ROOT/repo" rev-parse HEAD)"
CONFIGURATOR_SOURCE="$TMP_ROOT/repo/releases/${EXPECTED_RELEASE}/system/srvcc-configure-auto-updates"

python3 - "$TMP_ROOT/repo/deployment.json" "$EXPECTED_RELEASE" <<'PY'
import json,pathlib,sys
path=pathlib.Path(sys.argv[1])
expected=sys.argv[2]
data=json.loads(path.read_text(encoding='utf-8'))
assert data.get('enabled') is True, data
assert data.get('channel') == 'production', data
assert data.get('release_id') == expected, data
assert data.get('release_path') == f'releases/{expected}', data
print(f'BOOTSTRAP TARGET PASS: {expected}')
PY

# The current 1.x timer may be disabled and its oneshot service may be stuck in
# failed state. Do not rely on that transport to recover itself. Execute the
# repository's hash-validating transactional orchestrator directly once.
systemctl reset-failed srvcc-github-agent.service >/dev/null 2>&1 || true
log "Running transactional upgrade to ${EXPECTED_RELEASE} from ${REMOTE_SHA}"
bash "$TMP_ROOT/repo/deploy/deploy.sh" "$PROJECT" "$REMOTE_SHA"

python3 - "$EXPECTED_RELEASE" <<'PY'
import json,pathlib,sys
expected=sys.argv[1]
path=pathlib.Path('/var/lib/srv-control/release.json')
data=json.loads(path.read_text(encoding='utf-8'))
assert data.get('version') == expected, data
assert data.get('release_id') == expected, data
print(f'BOOTSTRAP RELEASE PASS: {expected}')
PY

# This recovery path exists specifically because the old automatic 5-minute
# updater failed and disabled its timer. A legacy config may therefore say
# manual even though that was not the operator-selected state. Always execute
# the configurator from the freshly cloned production tree so a transport-layer
# fix can refresh the installed helpers even when deploy.sh legitimately takes
# the already-applied/revalidation path and skips apply.
[[ -s "$CONFIGURATOR_SOURCE" ]] || fail "2.x update configurator source is unavailable after deployment"
log "Restoring automatic update mode: ${EXPECTED_INTERVAL} min"
bash "$CONFIGURATOR_SOURCE" \
    --repo "$REPO_URL" \
    --mode automatic \
    --interval-minutes "$EXPECTED_INTERVAL" \
    --no-check-now
[[ -x "$CONFIGURATOR" ]] || fail "2.x update configurator was not installed by recovery"

systemctl reset-failed srvcc-github-agent.service >/dev/null 2>&1 || true
systemctl is-enabled --quiet srvcc-github-agent.timer || fail "update timer is not enabled after bootstrap"
systemctl is-active --quiet srvcc-github-agent.timer || fail "update timer is not active after bootstrap"

log "Running one immediate 2.x updater cycle"
if ! systemctl start srvcc-github-agent.service; then
    systemctl status srvcc-github-agent.service --no-pager -l || true
    fail "2.x updater cycle failed after successful deployment"
fi
if systemctl is-failed --quiet srvcc-github-agent.service; then
    systemctl status srvcc-github-agent.service --no-pager -l || true
    fail "2.x updater remains failed"
fi

python3 - "$EXPECTED_INTERVAL" <<'PY'
import json,pathlib,sys
interval=int(sys.argv[1])
cfg=json.loads(pathlib.Path('/var/lib/srv-control/github-update-config.json').read_text(encoding='utf-8'))
status=json.loads(pathlib.Path('/var/lib/srv-control/github-update-status.json').read_text(encoding='utf-8'))
assert cfg.get('schema_version') == 4,cfg
assert cfg.get('mode') == 'automatic',cfg
assert cfg.get('interval_minutes') == interval,cfg
assert status.get('schema_version') == 4,status
assert status.get('last_check_at') or status.get('checked_at'),status
print('BOOTSTRAP UPDATER PASS: automatic interval=',interval,'last_check=',status.get('last_check_at') or status.get('checked_at'))
PY

python3 - <<'PY'
import json, urllib.request
with urllib.request.urlopen('http://127.0.0.1:8876/api/v1/health', timeout=15) as response:
    data=json.load(response)
assert data.get('ok') is True, data
print('BOOTSTRAP HEALTH PASS')
PY

# Re-run release acceptance after changing updater mode. This validates the
# final state that will actually remain on the server, including automatic
# timer state and the Minecraft compatibility backend through sudo -n.
log "Revalidating final automatic 2.0.0 state"
bash "$TMP_ROOT/repo/releases/2.0.0/acceptance-2.0.0.sh" "$PROJECT" "$REMOTE_SHA"

# Publish the accepted real-server state before repository cleanup. A successful
# publisher return means GitHub now has a fresh server-state created from the
# installed 2.0.0 release.
[[ -x "$STATE_PUBLISHER" ]] || fail "2.x state publisher is unavailable after deployment"
log "Publishing accepted 2.0.0 server-state"
"$STATE_PUBLISHER"

# Obsolete development branches are deleted only after all real-server gates
# above pass. Each branch must also be an ancestor of main; otherwise it is kept
# and the bootstrap stops rather than discarding unmerged history. Published
# release branches 1.1/1.2/1.3.x are intentionally not listed here.
log "Fetching full branch ancestry for safe 1.x cleanup"
git -C "$TMP_ROOT/repo" fetch --quiet --unshallow origin || true
git -C "$TMP_ROOT/repo" fetch --quiet --prune origin '+refs/heads/*:refs/remotes/origin/*'
MAIN_REF="$(git -C "$TMP_ROOT/repo" rev-parse refs/remotes/origin/main)"

for branch in "${OBSOLETE_UNPUBLISHED_BRANCHES[@]}"; do
    remote_ref="refs/remotes/origin/${branch}"
    if ! git -C "$TMP_ROOT/repo" show-ref --verify --quiet "$remote_ref"; then
        log "BRANCH CLEANUP SKIP: ${branch} is already absent"
        continue
    fi
    if ! git -C "$TMP_ROOT/repo" merge-base --is-ancestor "$remote_ref" "$MAIN_REF"; then
        fail "refusing to delete ${branch}: branch history is not fully contained in main"
    fi
    log "Deleting obsolete unpublished branch ${branch}"
    git -C "$TMP_ROOT/repo" push --quiet origin --delete "$branch"
done

log "BOOTSTRAP PASS: Control Center 2.0.0 installed; automatic 5-minute updater verified; server-state published; safe unpublished 1.x branches cleaned"
