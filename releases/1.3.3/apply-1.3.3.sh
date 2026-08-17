#!/usr/bin/env bash
set -Eeuo pipefail

RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE="${RELEASE_DIR}/apply.sh"
TMP="$(mktemp "${RELEASE_DIR}/.apply-1.3.3.XXXXXX.sh")"
PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
SESSION_KEY="/var/lib/srv-control/session.key"
SESSION_TMP=""
CONFIG="/var/lib/srv-control/github-update-config.json"
CONFIGURATOR="/usr/local/sbin/srvcc-configure-auto-updates"
PRESTATE="/var/lib/srv-deployment/prestate/${REMOTE_SHA}-1.3.3"
BACKUP_STATE="/var/lib/srv-deployment/backups/${REMOTE_SHA}-1.3.3/state"

restore_session_key() {
    if [[ ! -s "$SESSION_KEY" && -n "$SESSION_TMP" && -s "$SESSION_TMP" ]]; then
        install -m 0640 -o root -g srv-control "$SESSION_TMP" "$SESSION_KEY" || true
    fi
}
cleanup() {
    restore_session_key
    rm -f -- "$TMP"
    [[ -n "$SESSION_TMP" ]] && rm -f -- "$SESSION_TMP" || true
}
trap cleanup EXIT

# Persist rollback-critical state before the base apply changes any units.
install -d -m 0750 "$PRESTATE"
for unit in minecraft-update.timer srv-control-minecraft-auto-update.timer srvcc-github-agent.timer; do
    systemctl is-enabled "$unit" > "$PRESTATE/${unit}.enabled" 2>/dev/null || true
    systemctl is-active "$unit" > "$PRESTATE/${unit}.active" 2>/dev/null || true
done

# Keep an independent copy outside the deployment backup tree. This survives a
# failed apply/acceptance path and prevents authentication from disappearing
# while rollback is running.
if [[ -s "$SESSION_KEY" ]]; then
    SESSION_TMP="$(mktemp /var/lib/srv-control/.session-key.1.3.3.XXXXXX)"
    cp -a -- "$SESSION_KEY" "$SESSION_TMP"
    cp -a -- "$SESSION_KEY" "$PRESTATE/session.key"
fi

python3 - "$SOURCE" "$TMP" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]); dst=Path(sys.argv[2]); text=src.read_text(encoding='utf-8')
if 'RELEASE_ID="1.3.0"' not in text or 'RELEASE_VERSION="1.3.0"' not in text:
    raise SystemExit('1.3.3 apply release anchors missing')
text=text.replace('1.3.0','1.3.3')
dst.write_text(text,encoding='utf-8')
PY
chmod 0700 "$TMP"
bash "$TMP" "$@"
restore_session_key

# Keep the pre-state together with the normal release backup for acceptance
# rollback, while retaining PRESTATE until the transaction is fully accepted.
if [[ -d "$BACKUP_STATE" ]]; then
    cp -a "$PRESTATE/." "$BACKUP_STATE/"
fi

# Return the existing primary Bedrock server to the proven single-server path.
# The 1.3 multi-instance updater currently sees zero automatic instances on the
# real host, so it must not remain authoritative for this server.
systemctl disable --now srv-control-minecraft-auto-update.timer >/dev/null 2>&1 || true
systemctl enable --now minecraft-update.timer
install -m 0440 -o root -g root \
    "$RELEASE_DIR/system/sudoers-srv-control-minecraft-legacy" \
    /etc/sudoers.d/srv-control-minecraft-legacy
/usr/sbin/visudo -cf /etc/sudoers.d/srv-control-minecraft-legacy >/dev/null
/usr/local/sbin/srv-control-minecraft updater >/dev/null

# Patch the installed updater configurator so a failed product fingerprint is
# not retried forever by the automatic timer. Manual runs are still allowed to
# retry the same fingerprint after an operator has fixed the cause.
python3 - "$CONFIGURATOR" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); text=p.read_text(encoding='utf-8')
if 'LAST_FAILED_FINGERPRINT=' not in text:
    text=text.replace(
        'LAST_FINGERPRINT="${AGENT_ROOT}/last-release-fingerprint"\n',
        'LAST_FINGERPRINT="${AGENT_ROOT}/last-release-fingerprint"\nLAST_FAILED_FINGERPRINT="${AGENT_ROOT}/last-failed-release-fingerprint"\n',1)
    text=text.replace(
        'stored_fingerprint="$(cat "$LAST_FINGERPRINT" 2>/dev/null || true)"\n',
        'stored_fingerprint="$(cat "$LAST_FINGERPRINT" 2>/dev/null || true)"\nfailed_fingerprint="$(cat "$LAST_FAILED_FINGERPRINT" 2>/dev/null || true)"\n',1)
    marker='write_status update-available \'new product release is available\''
    guard='''if [[ "$OPERATION" == "apply" && "$ACTOR" == "system" && -n "$failed_fingerprint" && "$failed_fingerprint" == "$fingerprint" ]]; then
    write_status error 'automatic retry suppressed for previously failed release fingerprint' "$remote_sha" "$release_id" "$release_version" true
    log "Automatic retry suppressed for failed release ${release_id} fingerprint=${fingerprint}."
    publish_state
    exit 0
fi

'''
    if marker not in text: raise SystemExit('updater retry guard anchor missing')
    text=text.replace(marker,guard+marker,1)
    fail1="""if ! bash \"$DEPLOY_REPO/deploy/deploy.sh\" \"$PROJECT\" \"$remote_sha\" >> \"$LOG\" 2>&1; then
    write_status error 'deployment failed' \"$remote_sha\" \"$release_id\" \"$release_version\" true
"""
    fail1r="""if ! bash \"$DEPLOY_REPO/deploy/deploy.sh\" \"$PROJECT\" \"$remote_sha\" >> \"$LOG\" 2>&1; then
    printf '%s\\n' \"$fingerprint\" > \"$LAST_FAILED_FINGERPRINT\"; chmod 0640 \"$LAST_FAILED_FINGERPRINT\"
    write_status error 'deployment failed' \"$remote_sha\" \"$release_id\" \"$release_version\" true
"""
    if fail1 not in text: raise SystemExit('deployment failure anchor missing')
    text=text.replace(fail1,fail1r,1)
    fail2="""if [[ -x \"$DEPLOY_REPO/deploy/healthcheck.sh\" ]] && ! bash \"$DEPLOY_REPO/deploy/healthcheck.sh\" \"$PROJECT\" \"$remote_sha\" >> \"$LOG\" 2>&1; then
    write_status error 'deployment healthcheck failed' \"$remote_sha\" \"$release_id\" \"$release_version\" true
"""
    fail2r="""if [[ -x \"$DEPLOY_REPO/deploy/healthcheck.sh\" ]] && ! bash \"$DEPLOY_REPO/deploy/healthcheck.sh\" \"$PROJECT\" \"$remote_sha\" >> \"$LOG\" 2>&1; then
    printf '%s\\n' \"$fingerprint\" > \"$LAST_FAILED_FINGERPRINT\"; chmod 0640 \"$LAST_FAILED_FINGERPRINT\"
    write_status error 'deployment healthcheck failed' \"$remote_sha\" \"$release_id\" \"$release_version\" true
"""
    if fail2 not in text: raise SystemExit('healthcheck failure anchor missing')
    text=text.replace(fail2,fail2r,1)
    success="printf '%s\\n' \"$fingerprint\" > \"$LAST_FINGERPRINT\"\n"
    if success not in text: raise SystemExit('success fingerprint anchor missing')
    text=text.replace(success,success+'rm -f -- "$LAST_FAILED_FINGERPRINT"\n',1)
p.write_text(text,encoding='utf-8')
PY
chmod 0755 "$CONFIGURATOR"

# Recreate the agent from the patched configurator without triggering another
# deployment transaction. Preserve the currently selected mode and interval.
readarray -t cfg < <(python3 - "$CONFIG" <<'PY'
import json,pathlib,sys
try: d=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
except Exception: d={}
print(d.get('source') or 'https://github.com/filosoff31/srv-deployment.git')
print(d.get('mode') or 'automatic')
print(int(d.get('interval_minutes') or 5))
PY
)
"$CONFIGURATOR" --repo "${cfg[0]}" --mode "${cfg[1]}" --interval-minutes "${cfg[2]}" --no-check-now

printf 'APPLY 1.3.3 PASS: GitHub updater hardened; legacy Minecraft updater authoritative\n'
