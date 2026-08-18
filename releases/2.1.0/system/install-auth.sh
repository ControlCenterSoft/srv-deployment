#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

STATE_DIR="/var/lib/srv-control"
PAM_FILE="/etc/pam.d/srv-control"
KEYTAB="${STATE_DIR}/http.keytab"
NGINX_SITE="/etc/nginx/sites-available/srv-control"

fail() {
    printf 'AUTH INTEGRATION FAIL: %s\n' "$*" >&2
    exit 1
}

[[ "$(id -u)" -eq 0 ]] || fail "must run as root"
command -v apt-get >/dev/null 2>&1 || fail "apt-get is required"
command -v nginx >/dev/null 2>&1 || fail "nginx is required"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
    pamtester \
    libpam-winbind \
    libnginx-mod-http-auth-spnego \
    krb5-user

if command -v pam-auth-update >/dev/null 2>&1; then
    pam-auth-update --package >/dev/null 2>&1 || true
fi

cat > "$PAM_FILE" <<'EOF'
# SRV Control Center authenticates against the server's configured PAM stack.
@include common-auth
@include common-account
EOF
chmod 0644 "$PAM_FILE"

install -d -m 0750 -o srv-control -g srv-control "$STATE_DIR"
rm -f "$STATE_DIR/auth.json" "$STATE_DIR/admin-bootstrap.txt"

configure_samba_dc_keytab() {
    command -v samba-tool >/dev/null 2>&1 || return 1
    command -v testparm >/dev/null 2>&1 || return 1

    local role realm netbios fqdn account principal
    role="$(testparm -s --parameter-name='server role' 2>/dev/null | tr '[:upper:]' '[:lower:]' | xargs)"
    [[ "$role" == *"active directory domain controller"* ]] || return 1

    realm="$(testparm -s --parameter-name=realm 2>/dev/null | xargs)"
    netbios="$(testparm -s --parameter-name='netbios name' 2>/dev/null | xargs)"
    fqdn="$(hostname -f 2>/dev/null || hostname)"
    [[ -n "$realm" && -n "$netbios" && -n "$fqdn" ]] || return 1

    account="${netbios}$"
    principal="HTTP/${fqdn}"

    if ! samba-tool spn list "$account" 2>/dev/null | grep -Fqi "$principal"; then
        samba-tool spn add "$principal" "$account" >/dev/null
    fi

    rm -f "$KEYTAB"
    samba-tool domain exportkeytab "$KEYTAB" --principal="$principal" >/dev/null
    [[ -s "$KEYTAB" ]] || fail "Samba exported an empty HTTP keytab"
    chown root:www-data "$KEYTAB"
    chmod 0640 "$KEYTAB"

    printf '%s\n' "$realm" > "$STATE_DIR/sso-realm"
    chown root:srv-control "$STATE_DIR/sso-realm"
    chmod 0640 "$STATE_DIR/sso-realm"
    return 0
}

if ! configure_samba_dc_keytab; then
    if [[ -s /etc/krb5.keytab ]]; then
        install -m 0640 -o root -g www-data /etc/krb5.keytab "$KEYTAB"
    else
        rm -f "$KEYTAB"
    fi
fi

[[ -s "$NGINX_SITE" ]] || fail "SRV Control Center nginx site is missing"

python3 - "$NGINX_SITE" "$KEYTAB" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
keytab = Path(sys.argv[2])
text = path.read_text(encoding="utf-8")
start = "    # SRVCC-SPNEGO-BEGIN\n"
end = "    # SRVCC-SPNEGO-END\n"
if start in text and end in text:
    before, rest = text.split(start, 1)
    _, after = rest.split(end, 1)
    text = before + after

if keytab.is_file() and keytab.stat().st_size > 0:
    block = f'''    # SRVCC-SPNEGO-BEGIN
    location = /api/v1/auth/sso {{
        auth_gss on;
        auth_gss_keytab {keytab};
        auth_gss_service_name HTTP;
        auth_gss_allow_basic_fallback off;
        proxy_pass http://127.0.0.1:8876;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-SRVCC-Remote-User $remote_user;
        proxy_set_header Authorization "";
    }}
    # SRVCC-SPNEGO-END
'''
    marker = "    location / {\n"
    if marker not in text:
        raise SystemExit("nginx proxy location marker missing")
    text = text.replace(marker, block + marker, 1)

ordinary = "        proxy_set_header X-Forwarded-Proto $scheme;\n"
if "        proxy_set_header X-SRVCC-Remote-User \"\";\n" not in text:
    text = text.replace(
        ordinary,
        ordinary + '        proxy_set_header X-SRVCC-Remote-User "";\n',
        1,
    )

path.write_text(text, encoding="utf-8")
PY

nginx -t
systemctl reload nginx.service

printf 'AUTH INTEGRATION PASS: pam=%s spnego=%s\n' \
    "$PAM_FILE" \
    "$([[ -s "$KEYTAB" ]] && printf enabled || printf unavailable)"
