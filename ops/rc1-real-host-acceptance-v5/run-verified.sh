#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

[[ $EUID -eq 0 ]] || { printf 'ERROR: rc.1 real-host acceptance v5 must run as root\n' >&2; exit 1; }

V3_PARTS_COMMIT="5ea0c1ac68f4af19ece6ec7b3c15b7c2f3c10af6"
V3_EXPECTED_SHA256="00118701cb2a7dd0c11ae357c9e55f1ff8141bf6b4f978175c03e58e2a21a34e"
V5_EXPECTED_SHA256="2b470e04973851f79388531fbb30818c1cecc5a8f919b02a1b42adb11804b1e2"
BASE_URL="https://raw.githubusercontent.com/ControlCenterSoft/srv-deployment/${V3_PARTS_COMMIT}/ops/rc1-real-host-acceptance-v3"
WORK="$(mktemp -d /tmp/control-center-rc1-acceptance-v5-launch.XXXXXX)"
trap 'rm -rf -- "$WORK"' EXIT

for i in $(seq -w 0 15); do
  curl -fsSL "${BASE_URL}/part${i}" -o "$WORK/part${i}"
done
cat "$WORK"/part{00..15} > "$WORK/v3.sh"
printf '%s  %s\n' "$V3_EXPECTED_SHA256" "$WORK/v3.sh" | sha256sum -c -

python3 - "$WORK/v3.sh" "$WORK/v5.sh" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]).read_text()
old=src
src=src.replace('RC_COMMIT="9759cc339c24fd0405c5132b2ff4fc22d38c8a66"','RC_COMMIT="2b104ffa69d5f11b1a4de24fe92be95d89422acd"')
src=src.replace('RC_AMD64_SHA256="5c8873648e77d5ee75a3c1856ab677c602081db2766db9e4b2fbff8fdfb20c3a"','RC_AMD64_SHA256="0ecdfd3d44a2d5ba58d2d221527765e4014a0fa4fc62b7e73ac06718fb3a5121"')
src=src.replace('RC_ARM64_SHA256="8ebc8735c50f27177278bf75c1b2a468d724069236fe8134e3d19fee4d9d93c4"','RC_ARM64_SHA256="232393b745f0b649126a891f262d469a45eac97340856b1ce2952934780dbe74"')
src=src.replace('DIAG_SSH="git@github.com:ControlCenterSoft/control-center-server-diagnostics..git"','DIAG_SSH="git@github.com:ControlCenterSoft/control-center-server-diagnostics..git"\nDIAG_HTTPS="https://github.com/ControlCenterSoft/control-center-server-diagnostics..git"')
old_push='''push_report() {
  local repo="$BASE/diagnostics-repo" report_branch="reports/$HOST_SAFE/${START_TS}-rc1"
  rm -rf "$repo"
  git clone -q "$DIAG_SSH" "$repo" || return 1
  git -C "$repo" checkout -q -b "$report_branch"
  mkdir -p "$repo/reports/$HOST_SAFE/$START_TS"
  cp "$REPORT_FILE" "$repo/reports/$HOST_SAFE/$START_TS/report.txt"
  [[ -f "$DIAG_BUNDLE" ]] && cp "$DIAG_BUNDLE" "$repo/reports/$HOST_SAFE/$START_TS/control-center-diagnostics.tar.gz"
  git -C "$repo" config user.name 'control-center-acceptance'
  git -C "$repo" config user.email 'acceptance@control-center.invalid'
  git -C "$repo" add "reports/$HOST_SAFE/$START_TS"
  git -C "$repo" commit -q -m "Record rc.1 acceptance on $HOST_SAFE"
  git -C "$repo" push -q origin "$report_branch" || return 1
  REPORT_SENT="YES"
  REPORT_BRANCH="$report_branch"
  printf 'REPORT_SENT=YES\\nREPORT_BRANCH=%s\\n' "$report_branch"
}
'''
new_push='''push_report() {
  command -v git >/dev/null 2>&1 || { printf 'REPORT_SENT=NO\\n'; return 1; }
  local repo="$BASE/diagnostics-repo" report_branch="reports/$HOST_SAFE/${START_TS}-rc1" remote="" ssh_cmd=""
  rm -rf "$repo"
  if GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8' git ls-remote "$DIAG_SSH" >/dev/null 2>&1; then
    remote="$DIAG_SSH"
    ssh_cmd='ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8'
  elif GIT_TERMINAL_PROMPT=0 git ls-remote "$DIAG_HTTPS" >/dev/null 2>&1; then
    remote="$DIAG_HTTPS"
  else
    printf 'REPORT_SENT=NO\\n'
    return 1
  fi
  if [[ -n "$ssh_cmd" ]]; then
    GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="$ssh_cmd" git clone -q "$remote" "$repo" || { printf 'REPORT_SENT=NO\\n'; return 1; }
  else
    GIT_TERMINAL_PROMPT=0 git clone -q "$remote" "$repo" || { printf 'REPORT_SENT=NO\\n'; return 1; }
  fi
  git -C "$repo" checkout -q -b "$report_branch"
  mkdir -p "$repo/reports/$HOST_SAFE/$START_TS"
  cp "$REPORT_FILE" "$repo/reports/$HOST_SAFE/$START_TS/report.txt"
  [[ -f "$DIAG_BUNDLE" ]] && cp "$DIAG_BUNDLE" "$repo/reports/$HOST_SAFE/$START_TS/control-center-diagnostics.tar.gz"
  git -C "$repo" config user.name 'control-center-acceptance'
  git -C "$repo" config user.email 'acceptance@control-center.invalid'
  git -C "$repo" add "reports/$HOST_SAFE/$START_TS"
  git -C "$repo" commit -q -m "Record rc.1 acceptance on $HOST_SAFE"
  if [[ -n "$ssh_cmd" ]]; then
    GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="$ssh_cmd" git -C "$repo" push -q origin "$report_branch" || { printf 'REPORT_SENT=NO\\n'; return 1; }
  else
    GIT_TERMINAL_PROMPT=0 git -C "$repo" push -q origin "$report_branch" || { printf 'REPORT_SENT=NO\\n'; return 1; }
  fi
  REPORT_SENT="YES"
  REPORT_BRANCH="$report_branch"
  printf 'REPORT_SENT=YES\\nREPORT_BRANCH=%s\\n' "$report_branch"
}
'''
if old_push not in src:
    raise SystemExit('ERROR: immutable v3 push_report contract did not match')
src=src.replace(old_push,new_push)
if src == old:
    raise SystemExit('ERROR: no v5 patch applied')
Path(sys.argv[2]).write_text(src)
PY

printf '%s  %s\n' "$V5_EXPECTED_SHA256" "$WORK/v5.sh" | sha256sum -c -
bash -n "$WORK/v5.sh"
chmod 0700 "$WORK/v5.sh"
exec bash "$WORK/v5.sh"
