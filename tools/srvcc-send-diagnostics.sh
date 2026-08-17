#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

REPO_SLUG="${SRVCC_DIAGNOSTICS_REPO:-filosoff31/srv-deployment}"
REPO_URL="${SRVCC_DIAGNOSTICS_REPO_URL:-https://github.com/${REPO_SLUG}.git}"
STATE_BRANCH="${SRVCC_DIAGNOSTICS_BRANCH:-server-state}"
AGENT_ROOT="${SRVCC_AGENT_ROOT:-/var/lib/srvcc-agent}"
STATE_REPO="${SRVCC_STATE_REPO:-${AGENT_ROOT}/state-repo}"
STATE_PUBLISHER="${SRVCC_STATE_PUBLISHER:-/usr/local/sbin/srvcc-github-agent.state-publisher}"
DEST_REL="diagnostics/latest"

usage() {
    cat <<'EOF'
Usage: srvcc-send-diagnostics.sh [reason]

Collects a bounded, sanitized SRV Control Center diagnostic snapshot and pushes
it to diagnostics/latest on the server-state branch. It never reads .env files,
GitHub credential files, SSH private keys, browser/session stores, or user file
contents. A secret scan runs before git commit/push and blocks transmission if a
known secret pattern remains.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

[[ "$(id -u)" -eq 0 ]] || { echo "DIAGNOSTICS ERROR: run as root" >&2; exit 1; }

for command in git gh python3 flock systemctl journalctl timeout sha256sum hostname date tail; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "DIAGNOSTICS ERROR: missing command: $command" >&2
        exit 1
    }
done

REASON="${*:-manual}"
REASON="${REASON//$'\r'/ }"
REASON="${REASON//$'\n'/ }"
REASON="${REASON:0:200}"

if ! gh auth status --hostname github.com >/dev/null 2>&1; then
    echo "DIAGNOSTICS ERROR: GitHub CLI is not authenticated" >&2
    exit 1
fi

PUSH_PERMISSION="$(gh api "repos/${REPO_SLUG}" --jq '.permissions.push' 2>/dev/null || true)"
if [[ "$PUSH_PERMISSION" != "true" ]]; then
    LOGIN="$(gh api user --jq '.login' 2>/dev/null || true)"
    echo "DIAGNOSTICS ERROR: GitHub account ${LOGIN:-unknown} has no push permission to ${REPO_SLUG}" >&2
    exit 1
fi

gh auth setup-git >/dev/null 2>&1 || true
install -d -m 0750 "$AGENT_ROOT"

if [[ ! -d "$STATE_REPO/.git" ]]; then
    if [[ -x "$STATE_PUBLISHER" ]]; then
        "$STATE_PUBLISHER" >/dev/null 2>&1 || true
    fi
fi

if [[ ! -d "$STATE_REPO/.git" ]]; then
    rm -rf "$STATE_REPO"
    git clone --no-tags --single-branch --branch "$STATE_BRANCH" "$REPO_URL" "$STATE_REPO" >/dev/null 2>&1 || {
        echo "DIAGNOSTICS ERROR: cannot create state repository checkout" >&2
        exit 1
    }
fi

exec 9>"${AGENT_ROOT}/state-publish.lock"
if ! flock -w 90 9; then
    echo "DIAGNOSTICS ERROR: state repository is busy" >&2
    exit 1
fi

git -C "$STATE_REPO" remote set-url origin "$REPO_URL"

if [[ -n "$(git -C "$STATE_REPO" status --porcelain --untracked-files=all)" ]]; then
    echo "DIAGNOSTICS ERROR: state repository contains uncommitted changes; run the state publisher first" >&2
    exit 1
fi

if ! git -C "$STATE_REPO" fetch --prune origin "+refs/heads/${STATE_BRANCH}:refs/remotes/origin/${STATE_BRANCH}" >/dev/null 2>&1; then
    echo "DIAGNOSTICS ERROR: cannot fetch origin/${STATE_BRANCH}" >&2
    exit 1
fi

CURRENT_BRANCH="$(git -C "$STATE_REPO" branch --show-current)"
if [[ "$CURRENT_BRANCH" != "$STATE_BRANCH" ]]; then
    if git -C "$STATE_REPO" show-ref --verify --quiet "refs/heads/${STATE_BRANCH}"; then
        git -C "$STATE_REPO" switch "$STATE_BRANCH" >/dev/null
    else
        git -C "$STATE_REPO" switch -c "$STATE_BRANCH" --track "origin/${STATE_BRANCH}" >/dev/null
    fi
fi

HEAD_SHA="$(git -C "$STATE_REPO" rev-parse HEAD)"
REMOTE_SHA="$(git -C "$STATE_REPO" rev-parse "origin/${STATE_BRANCH}")"
if git -C "$STATE_REPO" merge-base --is-ancestor "$HEAD_SHA" "$REMOTE_SHA"; then
    git -C "$STATE_REPO" merge --ff-only "origin/${STATE_BRANCH}" >/dev/null
elif git -C "$STATE_REPO" merge-base --is-ancestor "$REMOTE_SHA" "$HEAD_SHA"; then
    : # local state commits are ahead; keep them and push together with diagnostics
else
    echo "DIAGNOSTICS ERROR: local and remote ${STATE_BRANCH} histories diverged" >&2
    exit 1
fi

WORK_ROOT="$(mktemp -d "${AGENT_ROOT}/diagnostics.XXXXXX")"
OUT="${WORK_ROOT}/latest"
mkdir -p "$OUT"
cleanup() { rm -rf "$WORK_ROOT"; }
trap cleanup EXIT

UTC_ID="$(date -u +%Y%m%dT%H%M%SZ)"
HOST="$(hostname -f 2>/dev/null || hostname)"
DIAGNOSTIC_ID="${UTC_ID}-$(hostname -s)-$$"

json_value() {
    local path="$1" key="$2"
    python3 - "$path" "$key" <<'PY' 2>/dev/null || true
import json, pathlib, sys
try:
    value=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')).get(sys.argv[2])
except Exception:
    value=None
print(value if isinstance(value,(str,int,float,bool)) else '')
PY
}

RELEASE_META="/var/lib/srv-control/release.json"
RELEASE_VERSION="$(json_value "$RELEASE_META" version)"
RELEASE_SHA="$(json_value "$RELEASE_META" git_sha)"

cat >"$OUT/manifest.env" <<EOF
schema_version=1
diagnostic_id=${DIAGNOSTIC_ID}
created_at=$(date -Is)
hostname=${HOST}
reason=${REASON}
release_version=${RELEASE_VERSION}
release_git_sha=${RELEASE_SHA}
state_branch=${STATE_BRANCH}
collector=srvcc-send-diagnostics
EOF

copy_text_file() {
    local src="$1" dest="$2" limit="${3:-1048576}"
    [[ -f "$src" && ! -L "$src" ]] || return 0
    tail -c "$limit" -- "$src" >"$OUT/$dest" 2>/dev/null || true
}

capture() {
    local dest="$1"; shift
    {
        echo "# command: $*"
        echo "# collected_at: $(date -Is)"
        set +e
        timeout 90 "$@" 2>&1
        rc=$?
        set -e
        echo
        echo "# exit_code: $rc"
    } >"$OUT/$dest"
}

# Structured state. No .env or credential stores are read.
copy_text_file /var/lib/srv-control/release.json release.json
copy_text_file /var/lib/srv-control/github-update-status.json github-update-status.json
copy_text_file /var/lib/srv-control/samba-domain-status.json samba-domain-status.json
copy_text_file /var/lib/srv-control/samba-shares-status.json samba-shares-status.json
copy_text_file /var/lib/srv-control/samba-shares.json samba-shares.json
copy_text_file /var/lib/srv-deployment/last-result.env deploy-last-result.env
copy_text_file /etc/samba/srv-control-shares.conf samba-managed-shares.conf
copy_text_file /var/log/srvcc-agent.log updater-tail.log 524288

python3 - "$OUT/share-action-results.json" <<'PY'
import json
from pathlib import Path
out=Path(__import__('sys').argv[1])
root=Path('/var/lib/srv-control/system-results')
items=[]
for p in root.glob('*.json'):
    try:
        d=json.loads(p.read_text(encoding='utf-8'))
    except Exception:
        continue
    action=str(d.get('action') or '')
    if action.startswith('samba-share') or action.startswith('samba-group') or action.startswith('samba-user'):
        items.append((p.stat().st_mtime, d))
items.sort(key=lambda x:x[0], reverse=True)
out.write_text(json.dumps([d for _,d in items[:30]],ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
PY

python3 - "$OUT/queued-samba-actions.json" <<'PY'
import json
from pathlib import Path
out=Path(__import__('sys').argv[1])
root=Path('/var/lib/srv-control/samba-actions')
items=[]
for p in sorted(root.glob('*.json'), key=lambda x:x.stat().st_mtime):
    try:
        d=json.loads(p.read_text(encoding='utf-8'))
    except Exception:
        continue
    # Payload values can be useful for reproducing validation failures, but are
    # redacted below before any Git operation.
    items.append(d)
out.write_text(json.dumps(items[-30:],ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
PY

{
    echo "# SRV Control Center service status"
    for unit in \
        srv-control.service \
        srv-control-samba-agent.service \
        srv-control-samba-monitor.service \
        srv-control-samba-shares-monitor.service \
        srvcc-github-agent.service \
        srvcc-github-agent.timer \
        samba-ad-dc.service samba.service smbd.service winbind.service; do
        echo
        echo "===== ${unit} ====="
        systemctl status "$unit" --no-pager -l 2>&1 || true
    done
} >"$OUT/services.txt"

{
    for unit in srv-control-samba-agent.service srv-control.service srvcc-github-agent.service samba-ad-dc.service; do
        echo
        echo "===== journal: ${unit} ====="
        journalctl -u "$unit" -n 220 --no-pager -o short-iso 2>&1 || true
    done
} >"$OUT/journals.txt"

{
    echo "===== testparm ====="
    testparm -s --suppress-prompt 2>&1 || true
    echo
    echo "===== workgroup ====="
    testparm -s --suppress-prompt --parameter-name=workgroup 2>&1 || true
    echo
    echo "===== server role ====="
    testparm -s --suppress-prompt --parameter-name='server role' 2>&1 || true
    echo
    echo "===== domain sid ====="
    net getdomainsid 2>&1 || true
    echo
    echo "===== users ====="
    samba-tool user list 2>&1 || true
    echo
    echo "===== groups ====="
    samba-tool group list 2>&1 || true
} >"$OUT/samba.txt"

{
    echo "===== /srv/shares top-level metadata ====="
    if [[ -d /srv/shares ]]; then
        find /srv/shares -maxdepth 1 -mindepth 1 -printf '%M %u:%g %p\n' 2>/dev/null | sort || true
        echo
        echo "===== /srv/shares ACL ====="
        if command -v getfacl >/dev/null 2>&1; then
            getfacl -p /srv/shares 2>&1 || true
        fi
    else
        echo "/srv/shares does not exist"
    fi
} >"$OUT/share-root.txt"

{
    echo "===== GitHub identity ====="
    gh api user --jq '.login' 2>&1 || true
    echo
    echo "===== repository permissions ====="
    gh api "repos/${REPO_SLUG}" --jq '{admin:.permissions.admin,maintain:.permissions.maintain,push:.permissions.push,pull:.permissions.pull}' 2>&1 || true
    echo
    echo "===== state repository ====="
    git -C "$STATE_REPO" status --short --branch 2>&1 || true
    git -C "$STATE_REPO" log -3 --oneline 2>&1 || true
} >"$OUT/github.txt"

{
    for file in \
        /opt/srv-control/static/js/shares.js \
        /opt/srv-control/app/routers/admin.py \
        /usr/local/libexec/srv-control-samba-admin \
        /usr/local/libexec/srv-control-samba-agent \
        /usr/local/libexec/srv-control-samba-shares-monitor; do
        if [[ -f "$file" ]]; then
            sha256sum "$file"
        else
            echo "MISSING $file"
        fi
    done
} >"$OUT/code-sha256.txt"

# Redact secrets from every collected text file before it is copied into Git.
python3 - "$OUT" <<'PY'
from pathlib import Path
import re, sys
root=Path(sys.argv[1])
private_key=re.compile(r'-----BEGIN [^-\n]*PRIVATE KEY-----.*?-----END [^-\n]*PRIVATE KEY-----',re.S|re.I)
patterns=[
    (re.compile(r'github_pat_[A-Za-z0-9_]{16,}'), '<redacted-github-token>'),
    (re.compile(r'gh[opusr]_[A-Za-z0-9_]{16,}'), '<redacted-github-token>'),
    (re.compile(r'AKIA[0-9A-Z]{16}'), '<redacted-aws-key>'),
    (re.compile(r'(?i)(authorization\s*:\s*(?:bearer|token)\s+)\S+'), r'\1<redacted>'),
    (re.compile(r'(?im)^(\s*(?:cookie|set-cookie)\s*:\s*).*$'), r'\1<redacted>'),
    (re.compile(r'https://([^:/\s]+):([^@/\s]+)@'), r'https://\1:<redacted>@'),
    (re.compile(r'(?im)^(\s*[^#\n]*(?:password|passwd|token|secret|api[_-]?key|client[_-]?secret)[^=:\n]*\s*[:=]\s*).+$'), r'\1<redacted>'),
]
for path in root.rglob('*'):
    if not path.is_file() or path.is_symlink():
        continue
    data=path.read_text(encoding='utf-8',errors='replace')
    data=private_key.sub('<redacted-private-key>',data)
    for pattern,repl in patterns:
        data=pattern.sub(repl,data)
    # Bound each diagnostic component after redaction to avoid accidental huge pushes.
    if len(data)>2_000_000:
        data='[truncated to last 2 MB]\n'+data[-2_000_000:]
    path.write_text(data,encoding='utf-8')
PY

# Block the upload if obvious credential material survived redaction.
python3 - "$OUT" <<'PY'
from pathlib import Path
import re, sys
root=Path(sys.argv[1])
checks=[
    re.compile(r'-----BEGIN [^-\n]*PRIVATE KEY-----',re.I),
    re.compile(r'github_pat_[A-Za-z0-9_]{16,}'),
    re.compile(r'gh[opusr]_[A-Za-z0-9_]{16,}'),
    re.compile(r'AKIA[0-9A-Z]{16}'),
    re.compile(r'(?i)authorization\s*:\s*(?:bearer|token)\s+(?!<redacted>)\S+'),
]
findings=[]
for path in root.rglob('*'):
    if not path.is_file() or path.is_symlink():
        continue
    text=path.read_text(encoding='utf-8',errors='replace')
    for check in checks:
        if check.search(text):
            findings.append(f'{path.name}: {check.pattern}')
            break
if findings:
    print('DIAGNOSTICS SECURITY BLOCK: possible secret remained after redaction',file=sys.stderr)
    for item in findings:
        print(' - '+item,file=sys.stderr)
    raise SystemExit(3)
PY

TOTAL_BYTES="$(du -sb "$OUT" | awk '{print $1}')"
if (( TOTAL_BYTES > 12000000 )); then
    echo "DIAGNOSTICS ERROR: sanitized snapshot is unexpectedly large (${TOTAL_BYTES} bytes); upload blocked" >&2
    exit 1
fi

echo "total_bytes=${TOTAL_BYTES}" >>"$OUT/manifest.env"

DEST="${STATE_REPO}/${DEST_REL}"
rm -rf "$DEST"
mkdir -p "$DEST"
cp -a "$OUT/." "$DEST/"

git -C "$STATE_REPO" add -A -- "$DEST_REL"
if git -C "$STATE_REPO" diff --cached --quiet -- "$DEST_REL"; then
    echo "DIAGNOSTICS PASS: snapshot is unchanged; nothing to push"
    echo "branch=${STATE_BRANCH}"
    echo "path=${DEST_REL}"
    exit 0
fi

git -C "$STATE_REPO" config user.name "SRV Control Diagnostics"
git -C "$STATE_REPO" config user.email "srv-control@localhost"
git -C "$STATE_REPO" commit -m "diagnostics: ${HOST} ${DIAGNOSTIC_ID}" >/dev/null

if ! git -C "$STATE_REPO" push origin "HEAD:${STATE_BRANCH}" >/dev/null 2>&1; then
    echo "DIAGNOSTICS ERROR: failed to push sanitized diagnostics to ${STATE_BRANCH}" >&2
    exit 1
fi

COMMIT="$(git -C "$STATE_REPO" rev-parse HEAD)"
echo "DIAGNOSTICS SENT"
echo "diagnostic_id=${DIAGNOSTIC_ID}"
echo "branch=${STATE_BRANCH}"
echo "path=${DEST_REL}"
echo "commit=${COMMIT}"
echo "Next step: in ChatGPT write only: проверь логи"
