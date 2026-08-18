#!/usr/bin/env bash
set -Eeuo pipefail
host="$(hostname -f)"
ss -ltnH | awk '{print $4}' | grep -Eq '(^|:|\])443$' || { echo "ACCEPTANCE 2.1.3 FAIL: 443 not listening" >&2; exit 1; }
curl -fsSI "http://127.0.0.1/" -H "Host: $host" | grep -Eqi '^location: https://' || { echo "ACCEPTANCE 2.1.3 FAIL: HTTP redirect missing" >&2; exit 1; }
curl -fkfsS "https://127.0.0.1/api/v1/health" -H "Host: $host" >/dev/null
openssl x509 -in /var/lib/srv-control/tls/server.crt -noout -ext subjectAltName | grep -Fqi "DNS:$host"
nginx -T 2>/dev/null | grep -Fq 'proxy_set_header X-SRVCC-Remote-User "";'
/usr/local/libexec/control-center-chrony status >/dev/null
echo "ACCEPTANCE 2.1.3 PASS"
