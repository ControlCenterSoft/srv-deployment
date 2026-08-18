#!/usr/bin/env bash
set -Eeuo pipefail
umask 027
PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID=2.1.4
RELEASE_VERSION=2.1.4
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$RELEASE_DIR/../.." && pwd -P)"
BASE="$REPO_ROOT/releases/2.1.2"
STATE=/var/lib/srv-control
META="$STATE/release.json"
BACKUP="/var/lib/srv-deployment/backups/${REMOTE_SHA}-${RELEASE_ID}"
fail(){ echo "APPLY 2.1.4 FAIL: $*" >&2; exit 1; }
version(){ python3 - "$META" <<'PY'
import json,pathlib,sys
try: data=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
except Exception: data={}
print(data.get('version') or '')
PY
}
ORIGINAL_SOURCE="$(version)"
case "$ORIGINAL_SOURCE" in
  1.3.8|2.0.0|2.1.0|2.1.1|2.1.2) ;;
  *) fail "unsupported source version: ${ORIGINAL_SOURCE:-missing}" ;;
esac
install -d -m 0750 "$BACKUP/state"
printf '%s\n' "$ORIGINAL_SOURCE" > "$BACKUP/state/original-source-version"
cp -a "$META" "$BACKUP/state/release.json.before"
if [[ "$ORIGINAL_SOURCE" != "2.1.2" ]]; then
  echo "Applying frozen 2.1.2 baseline before 2.1.4 installer repair"
  bash "$BASE/apply-2.1.2.sh" "$PROJECT" "$REMOTE_SHA"
fi
[[ "$(version)" == "2.1.2" ]] || fail "2.1.2 baseline was not established"
# The runtime application remains identical to accepted 2.1.2. The product
# change is the repository clean-install path. Prove that the consolidated
# install image can be reconstructed from the published frozen layers before
# advancing release metadata.
tmp="$(mktemp -d /var/tmp/control-center-install-2.1.4.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
python3 "$REPO_ROOT/installer/build-install-payload.py" \
  "$REPO_ROOT" "$REPO_ROOT/installer/install-profile.json" "$tmp/payload" \
  > "$BACKUP/state/install-payload-build.json" \
  || fail "consolidated clean-install payload could not be built"
[[ -s "$tmp/payload/app/main.py" ]] || fail "assembled app missing"
[[ -s "$tmp/payload/templates/minecraft.html" ]] || fail "assembled Minecraft template missing"
[[ -s "$tmp/payload/static/js/minecraft-status-2.1.2.js" ]] || fail "assembled Minecraft status layer missing"
rm -rf "$tmp"
trap - EXIT
sync_time="$(date -Is)"
python3 - "$META" "$RELEASE_VERSION" "$RELEASE_ID" "$sync_time" "$REMOTE_SHA" <<'PY'
import grp,json,os,pathlib,sys,tempfile
path=pathlib.Path(sys.argv[1]); path.parent.mkdir(parents=True,exist_ok=True)
payload={'version':sys.argv[2],'release_id':sys.argv[3],'synced_at':sys.argv[4],'git_sha':sys.argv[5]}
try: gid=grp.getgrnam('srv-control').gr_gid
except KeyError: gid=0
fd,tmp=tempfile.mkstemp(prefix='.release-2.1.4.',dir=str(path.parent))
try:
    os.fchown(fd,0,gid); os.fchmod(fd,0o640)
    with os.fdopen(fd,'w',encoding='utf-8') as h:
        json.dump(payload,h,ensure_ascii=False,indent=2); h.write('\n'); h.flush(); os.fsync(h.fileno())
    os.replace(tmp,path)
finally:
    try: os.unlink(tmp)
    except FileNotFoundError: pass
PY
curl -fsS --max-time 10 http://127.0.0.1:8876/api/v1/health >/dev/null \
  || fail "Control Center health endpoint unavailable"
echo "APPLY 2.1.4 PASS: clean installer now assembles frozen baseline+deltas; running 2.1.2 runtime preserved; source=$ORIGINAL_SOURCE"
