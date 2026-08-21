#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

TOKEN_FILE='/etc/control-center-diagnostics-agent/github-token'
[[ -s "$TOKEN_FILE" ]] || { echo 'missing diagnostics token' >&2; exit 1; }
OUT="$(mktemp /tmp/platform-v2-diagnostic.XXXXXX.txt)"
cleanup(){ rm -f -- "$OUT"; }
trap cleanup EXIT

{
  echo '=== RUNTIME ==='
  /usr/local/lib/control-center/current/control-center build-info --field version || true
  /usr/local/lib/control-center/current/control-center build-info --field commit || true
  echo
  echo '=== PREPARE UNIT ==='
  systemctl show control-center-platform-v2-prepare.service \
    -p LoadState -p ActiveState -p SubState -p Result -p ExecMainStatus \
    -p NoNewPrivileges -p ProtectSystem -p ReadWritePaths -p CapabilityBoundingSet --no-pager || true
  echo
  echo '=== PREPARE JOURNAL ==='
  journalctl -u control-center-platform-v2-prepare.service -n 120 --no-pager -o short-iso-precise || true
  echo
  echo '=== TARGET STATE ==='
  stat -c '%A %U:%G %n' /usr/local/sbin/control-center-update /etc/systemd/system/control-center-privileged-worker.service 2>&1 || true
  sha256sum /usr/local/sbin/control-center-update /etc/systemd/system/control-center-privileged-worker.service 2>&1 || true
  echo -n 'worker_active='; systemctl is-active control-center-privileged-worker.service || true
  echo -n 'worker_enabled='; systemctl is-enabled control-center-privileged-worker.service || true
  echo
  echo '=== MIGRATION STATE ==='
  find /var/lib/control-center/platform-migrations -maxdepth 1 -type f -printf '%f %m %u:%g\n' 2>/dev/null | sort || true
} >"$OUT" 2>&1

python3 - "$TOKEN_FILE" "$OUT" <<'PY'
import base64, json, pathlib, re, sys, urllib.error, urllib.parse, urllib.request

token_path, out_path = sys.argv[1:]
token = pathlib.Path(token_path).read_text(encoding='utf-8').strip()
text = pathlib.Path(out_path).read_text(encoding='utf-8', errors='replace')[-60000:]
patterns = [
    re.compile(r'(?i)(authorization|cookie|set-cookie)\s*:\s*[^\r\n]+'),
    re.compile(r'(?i)(password|passwd|secret|token|api[_-]?key)\s*[:=]\s*[^\s,;]+'),
    re.compile(r'github_pat_[A-Za-z0-9_]+'), re.compile(r'gh[pousr]_[A-Za-z0-9_]+'),
    re.compile(r'sk-[A-Za-z0-9_-]{16,}'), re.compile(r'(?i)bearer\s+[A-Za-z0-9._~+/=-]+'),
]
for pattern in patterns:
    text = pattern.sub('<REDACTED>', text)
repo = 'ControlCenterSoft/control-center-server-diagnostics'
branch = 'agent-state'
path = 'ops-reports/ruvds-pr1re/platform-v2-prepare-diagnostic.json'
owner, name = repo.split('/', 1)
encoded = '/'.join(urllib.parse.quote(part, safe='') for part in path.split('/'))
base = f'https://api.github.com/repos/{owner}/{name}/contents/{encoded}'
headers = {
    'Accept': 'application/vnd.github+json',
    'Authorization': f'Bearer {token}',
    'User-Agent': 'control-center-chatssh-bounded-diagnostic/1',
    'X-GitHub-Api-Version': '2022-11-28',
}
sha = None
try:
    req = urllib.request.Request(base + '?ref=' + urllib.parse.quote(branch, safe=''), headers=headers)
    with urllib.request.urlopen(req, timeout=15) as response:
        current = json.load(response)
        sha = current.get('sha')
except urllib.error.HTTPError as exc:
    if exc.code != 404:
        raise
payload_obj = {'schema': 1, 'kind': 'platform-v2-prepare-diagnostic', 'server_id': 'ruvds-pr1re', 'content': text}
content = json.dumps(payload_obj, ensure_ascii=False, indent=2) + '\n'
payload = {
    'message': 'Publish bounded platform-v2 prepare diagnostic',
    'content': base64.b64encode(content.encode()).decode(),
    'branch': branch,
}
if sha:
    payload['sha'] = sha
req = urllib.request.Request(base, data=json.dumps(payload).encode(), method='PUT', headers={**headers, 'Content-Type': 'application/json'})
with urllib.request.urlopen(req, timeout=20) as response:
    if response.status not in (200, 201):
        raise SystemExit(f'publish failed: HTTP {response.status}')
PY

echo 'PLATFORM_V2_DIAGNOSTIC_PUBLISHED=1'
