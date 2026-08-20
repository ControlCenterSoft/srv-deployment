from __future__ import annotations

import time
from pathlib import Path

from flask import jsonify, request
from psycopg.types.json import Jsonb

import database
import release_111

DNS_MODULE = Path('/var/lib/control-center-system/modules/dns.json')
STORAGE_MODULE = Path('/var/lib/control-center-system/modules/storage.json')
DNS_PENDING = Path('/var/lib/control-center/dns-pending.json')
STORAGE_PENDING = Path('/var/lib/control-center/storage-pending.json')
SAMBA_PENDING = Path('/run/control-center/samba-provision.json')
DOMAIN_REMOVE_PENDING = Path('/run/control-center/domain-remove.json')


def _active(main, unit):
    rc, out, _ = main._run(['systemctl', 'is-active', unit], 3)
    return rc == 0 and out.strip() in {'active', 'activating', 'reloading'}


def _managed_storage(main):
    m = main._read_json(STORAGE_MODULE, {})
    return m if m.get('installed') and m.get('provider') == 'samba_standalone' else {}


def _managed_dns(main):
    m = main._read_json(DNS_MODULE, {})
    return m if m.get('installed') and m.get('provider') == 'unbound' else {}


def _protected_dir_probe(path: Path):
    """Return True/False when visible, None when intentionally inaccessible.

    Domain storage is root/service-owned and the unprivileged Web process does
    not need traverse permission. A PermissionError is therefore not evidence
    that the share is absent. Root lifecycle workers remain responsible for
    creating/removing the path and publishing the trusted module state.
    """
    try:
        return path.is_dir()
    except PermissionError:
        return None
    except OSError:
        return False


def _root_acceptance_check(evidence, key, message):
    recorded_at = int(evidence.get('recorded_at') or 0)
    return {
        'ok': evidence.get(key) is True and recorded_at > 0,
        'value': {
            'source': 'privileged-domain-activation-acceptance',
            'recorded_at': recorded_at,
        },
        'message': message,
    }


def register(app, main):
    original_readiness = release_111._readiness

    def readiness_dependencies_111(main_arg, body=None, persist=True):
        body = dict(body or {})
        storage = _managed_storage(main_arg)
        dns = _managed_dns(main_arg)
        if storage:
            body['replace_existing'] = True
        payload = original_readiness(main_arg, body, persist=False)
        checks = dict(payload.get('checks') or {})

        if storage:
            checks['existing_samba'] = {
                'ok': True,
                'severity': 'info',
                'value': '/etc/samba/smb.conf',
                'message': 'Control Center Сетевое хранилище будет переведено в доменный SMB; исходное состояние сохранится для rollback/удаления Домена.',
            }
            checks['smb_445'] = {
                'ok': True,
                'severity': 'info',
                'value': checks.get('smb_445', {}).get('value') or [],
                'message': 'Порт 445 занят управляемым standalone SMB и будет освобождён в контролируемом cutover.',
            }
            checks['storage_dependency'] = {
                'ok': True,
                'severity': 'info',
                'value': {'provider': storage.get('provider'), 'share_name': storage.get('share_name'), 'path': storage.get('path')},
                'message': 'Обязательное Сетевое хранилище уже установлено и будет интегрировано в Домен.',
            }
        else:
            checks['storage_dependency'] = {
                'ok': True,
                'severity': 'info',
                'value': 'auto-domain-smb',
                'message': 'Сетевое хранилище будет автоматически активировано как обязательная часть Домена.',
            }

        if dns:
            checks['dns_53'] = {
                'ok': True,
                'severity': 'info',
                'value': {'provider': 'unbound', 'ipv4': dns.get('ipv4'), 'interface': dns.get('interface')},
                'message': 'Standalone DNS Control Center будет безопасно остановлен на время cutover; после создания Домена используется Samba Internal DNS.',
            }
            checks['dns_dependency'] = {
                'ok': True,
                'severity': 'info',
                'value': {'provider': dns.get('provider'), 'forwarders': dns.get('forwarders') or []},
                'message': 'DNS уже установлен; standalone-состояние будет сохранено и восстановлено после удаления Домена.',
            }
        else:
            checks['dns_dependency'] = {
                'ok': True,
                'severity': 'info',
                'value': 'auto-samba-internal',
                'message': 'DNS будет автоматически активирован как Samba Internal DNS при создании Домена.',
            }

        external_ad = False
        if Path('/etc/samba/smb.conf').exists() and not storage:
            rc, out, _ = main_arg._run(['testparm', '-s', '--parameter-name=server role'], 5)
            external_ad = rc == 0 and 'active directory domain controller' in (out or '').lower()
        checks['external_ad_takeover'] = {
            'ok': not external_ad,
            'severity': 'blocker',
            'value': 'detected' if external_ad else 'none',
            'message': 'Внешний Samba AD-DC не обнаружен' if not external_ad else 'Обнаружен внешний Samba AD-DC. Автоматический takeover запрещён; требуется отдельный import/migration lifecycle.',
        }

        busy = []
        if DNS_PENDING.exists() or _active(main_arg, 'control-center-dns-apply.service'):
            busy.append('DNS')
        if STORAGE_PENDING.exists() or _active(main_arg, 'control-center-storage-apply.service'):
            busy.append('Сетевое хранилище')
        checks['dependency_workers'] = {
            'ok': not busy,
            'severity': 'blocker',
            'value': busy,
            'message': 'Dependency workers свободны' if not busy else 'Дождитесь завершения операций: ' + ', '.join(busy),
        }

        blockers = [k for k, v in checks.items() if v.get('severity') == 'blocker' and not v.get('ok')]
        warnings = [k for k, v in checks.items() if v.get('severity') == 'warning' and not v.get('ok')]
        payload['checks'] = checks
        payload['blockers'] = blockers
        payload['warnings'] = warnings
        payload['ready'] = not blockers
        details = dict(payload.get('details') or {})
        details['dependencies'] = {
            'dns': 'managed-standalone-transition' if dns else 'auto-domain',
            'storage': 'managed-standalone-transition' if storage else 'auto-domain',
            'domain_requires_dns': True,
            'domain_requires_storage': True,
            'restore_prestate_on_domain_remove': True,
            'external_ad_takeover_supported': False,
        }
        payload['details'] = details
        if persist:
            try:
                main_arg._write_json(release_111.SAMBA_READINESS, payload)
            except Exception:
                pass
            try:
                with database.connect() as conn:
                    conn.execute(
                        "INSERT INTO control_center.ad_dc_readiness_runs(hostname,fqdn,ready,blockers,warnings,checks,details) VALUES(%s,%s,%s,%s,%s,%s,%s)",
                        (payload['hostname'], payload['fqdn'], payload['ready'], Jsonb(blockers), Jsonb(warnings), Jsonb(checks), Jsonb(details)),
                    )
            except Exception:
                payload['persistence'] = 'system-json'
        return payload

    release_111._readiness = readiness_dependencies_111

    def health_dependencies_111(main_arg, persist=True):
        module = main_arg._read_json(release_111.SAMBA_MODULE, {})
        if not module.get('managed') or module.get('state') != 'active':
            return {
                'healthy': False,
                'state': 'not-provisioned',
                'checks': {},
                'details': module,
                'checked_at': int(time.time()),
            }

        ip = str(module.get('ipv4') or '')
        realm = str(module.get('realm') or '').lower()
        fqdn = str(module.get('fqdn') or '')
        evidence = module.get('root_acceptance') if isinstance(module.get('root_acceptance'), dict) else {}
        checks = {}

        rc, out, err = main_arg._run(['systemctl', 'is-active', 'samba-ad-dc.service'], 4)
        checks['service'] = {
            'ok': rc == 0 and out.strip() == 'active',
            'value': out.strip() or err.strip(),
            'message': 'samba-ad-dc active',
        }
        rc, out, err = main_arg._run(['samba-tool', 'domain', 'info', ip], 8)
        checks['domain_info'] = {
            'ok': rc == 0,
            'value': out[-1500:] if out else err[-1500:],
            'message': 'Live unprivileged domain discovery',
        }

        # DRS, SYSVOL and directory-group inspection require access to Samba's
        # private LDB and must never be granted to the Web service account.
        # They are therefore revalidated by the privileged activation worker
        # immediately before it marks the Domain active. The Web endpoint
        # consumes only that root-owned module evidence and combines it with
        # live unprivileged service/DNS checks.
        checks['replication'] = _root_acceptance_check(
            evidence,
            'replication',
            'DRS replication accepted by privileged Domain activation worker',
        )
        checks['sysvol'] = _root_acceptance_check(
            evidence,
            'sysvol',
            'SYSVOL ACL accepted by privileged Domain activation worker',
        )

        for key, record in [
            ('dns_a', fqdn),
            ('dns_ldap', f'_ldap._tcp.{realm}'),
            ('dns_kerberos', f'_kerberos._udp.{realm}'),
        ]:
            qtype = 'A' if key == 'dns_a' else 'SRV'
            rc, out, err = main_arg._run(['host', '-W', '3', '-t', qtype, record, ip], 6)
            checks[key] = {
                'ok': rc == 0,
                'value': out.strip() or err.strip(),
                'message': f'DNS {qtype} {record}',
            }

        dns = main_arg._read_json(DNS_MODULE, {})
        storage = main_arg._read_json(STORAGE_MODULE, {})
        checks['dns_dependency'] = {
            'ok': bool(dns.get('installed') and dns.get('provider') == 'samba_internal' and 'domain' in (dns.get('dependency_by') or [])),
            'value': dns,
            'message': 'Samba Internal DNS dependency',
        }
        share_path = Path(str(storage.get('path') or '/srv/control-center/storage/public'))
        path_exists = _protected_dir_probe(share_path)
        marker = False
        try:
            marker = '# BEGIN CONTROL CENTER STORAGE' in Path('/etc/samba/smb.conf').read_text(errors='replace')
        except Exception:
            pass
        storage_state_ok = bool(
            storage.get('installed')
            and storage.get('provider') == 'samba_ad_dc'
            and 'domain' in (storage.get('dependency_by') or [])
        )
        checks['storage_dependency'] = {
            'ok': bool(storage_state_ok and path_exists is not False and marker),
            'value': {
                'module': storage,
                'path_exists': path_exists,
                'path_probe': 'protected' if path_exists is None else 'visible',
                'config_marker': marker,
            },
            'message': 'Domain SMB storage dependency; protected path is validated by the root lifecycle worker and trusted module state.',
        }
        rc, out, err = main_arg._run(['systemctl', 'is-active', 'control-center-authd.service'], 4)
        checks['portal_auth_daemon'] = {
            'ok': rc == 0 and out.strip() == 'active',
            'value': out.strip() or err.strip(),
            'message': 'Local/domain portal auth daemon',
        }
        checks['portal_domain_admin_group'] = _root_acceptance_check(
            evidence,
            'portal_domain_admin_group',
            'Domain bootstrap admin group accepted by privileged Domain activation worker',
        )
        checks['administrator_sid_uid0'] = _root_acceptance_check(
            evidence,
            'administrator_sid_uid0',
            'Built-in Administrator SID-to-UID mapping accepted by privileged Domain activation worker',
        )

        healthy = all(bool(v.get('ok')) for v in checks.values())
        payload = {
            'healthy': healthy,
            'state': 'healthy' if healthy else 'degraded',
            'checks': checks,
            'details': module,
            'checked_at': int(time.time()),
        }
        if persist:
            try:
                module['health_state'] = payload['state']
                module['last_health_at'] = payload['checked_at']
                main_arg._write_json(release_111.SAMBA_MODULE, module)
            except Exception:
                pass
            try:
                profile = 'primary-' + str(module.get('netbios_domain') or '').lower()
                with database.connect() as conn:
                    conn.execute(
                        "INSERT INTO control_center.ad_dc_health_runs(profile_id,healthy,checks,details) VALUES(%s,%s,%s,%s)",
                        (profile, healthy, Jsonb(checks), Jsonb(module)),
                    )
                    conn.execute(
                        "UPDATE control_center.ad_dc_profiles SET health_state=%s,last_health_at=now(),updated_at=now() WHERE profile_id=%s",
                        (payload['state'], profile),
                    )
            except Exception:
                pass
        return payload

    release_111._quick_health = health_dependencies_111

    def dependency_request_guard_111():
        path = request.path
        if path == '/api/samba/provision' and request.method == 'POST':
            body = request.get_json(silent=True)
            if isinstance(body, dict) and _managed_storage(main):
                body['replace_existing'] = True
            if DNS_PENDING.exists() or STORAGE_PENDING.exists() or _active(main, 'control-center-dns-apply.service') or _active(main, 'control-center-storage-apply.service'):
                return jsonify(ok=False, error='Дождитесь завершения операций DNS/Сетевого хранилища перед созданием Домена.'), 409
        if path in {'/api/market/dns', '/api/dns/config', '/api/market/storage', '/api/storage/config'} and request.method == 'POST':
            if SAMBA_PENDING.exists() or DOMAIN_REMOVE_PENDING.exists() or _active(main, 'control-center-samba-apply.service') or _active(main, 'control-center-domain-destroy.service'):
                return jsonify(ok=False, error='Операции DNS/Сетевого хранилища заблокированы на время изменения Домена.'), 409
        return None

    app.before_request_funcs.setdefault(None, []).insert(0, dependency_request_guard_111)
