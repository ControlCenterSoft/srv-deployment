#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${SOURCE_DIR}/apply-1.3.3.sh" "$@"

# 1.3.4 is installer-only. Keep the proven 1.3.3 payload and mark the patch
# version only after the 1.3.3 apply transaction has completed successfully.
python3 - "${2:-unknown}" <<'PY'
import json, pathlib, sys, tempfile, os
path=pathlib.Path('/var/lib/srv-control/release.json')
data=json.loads(path.read_text(encoding='utf-8'))
data['version']='1.3.4'
data['release_id']='1.3.4'
if sys.argv[1] and sys.argv[1] != 'unknown':
    data['git_sha']=sys.argv[1]
fd,tmp=tempfile.mkstemp(prefix='.release-1.3.4.',dir=str(path.parent))
try:
    with os.fdopen(fd,'w',encoding='utf-8') as handle:
        json.dump(data,handle,ensure_ascii=False,indent=2)
        handle.write('\n')
    os.chmod(tmp,0o640)
    os.replace(tmp,path)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
PY

printf 'APPLY 1.3.4 PASS: 1.3.3 payload applied; release metadata advanced to 1.3.4\n'
