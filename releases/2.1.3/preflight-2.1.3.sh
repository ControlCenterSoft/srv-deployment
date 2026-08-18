#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo "PREFLIGHT 2.1.3 FAIL: root required" >&2; exit 1; }
for c in bash python3 nginx openssl systemctl hostname; do command -v "$c" >/dev/null || { echo "PREFLIGHT 2.1.3 FAIL: missing $c" >&2; exit 1; }; done
[[ -s /var/lib/srv-control/release.json ]] || { echo "PREFLIGHT 2.1.3 FAIL: release metadata missing" >&2; exit 1; }
python3 - <<'PY'
import json
p=json.load(open('/var/lib/srv-control/release.json',encoding='utf-8'))
assert p.get('version')=='2.1.2', p
print('PREFLIGHT 2.1.3 PASS: source=2.1.2')
PY
