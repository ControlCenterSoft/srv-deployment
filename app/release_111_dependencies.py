from __future__ import annotations

from pathlib import Path

from flask import jsonify, request

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


def register(app, main):
    original_readiness = release_111._readiness

    def readiness_dependencies_111(main_arg, body=None, persist=True):
        body = dict(body or {})
        storage = _managed_storage(main_arg)
        dns = _managed_dns(main_arg)
        if storage:
            # The existing smb.conf is not an external takeover: it belongs to
            # Control Center Storage and is deliberately transitioned to the DC
            # role. The root pre-stage snapshots it and rollback restores it.
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
                'value': 'auto-install',
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
                'message': 'DNS уже установлен; его standalone-состояние будет сохранено и восстановлено после удаления Домена.',
            }
        else:
            checks['dns_dependency'] = {
                'ok': True,
                'severity': 'info',
                'value': 'auto-install',
                'message': 'DNS будет автоматически активирован как Samba Internal DNS при создании Домена.',
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
        }
        payload['details'] = details
        if persist:
            try:
                main_arg._write_json(release_111.SAMBA_READINESS, payload)
            except Exception:
                pass
        return payload

    release_111._readiness = readiness_dependencies_111

    def dependency_request_guard_111():
        path = request.path
        if path == '/api/samba/provision' and request.method == 'POST':
            body = request.get_json(silent=True)
            if isinstance(body, dict) and _managed_storage(main):
                # request.get_json() is cached by Flask; mutating this dict makes
                # the existing provision route/root pending request explicitly
                # acknowledge replacement of Control Center's own smb.conf.
                body['replace_existing'] = True
            if DNS_PENDING.exists() or STORAGE_PENDING.exists() or _active(main, 'control-center-dns-apply.service') or _active(main, 'control-center-storage-apply.service'):
                return jsonify(ok=False, error='Дождитесь завершения операций DNS/Сетевого хранилища перед созданием Домена.'), 409
        if path in {'/api/market/dns', '/api/dns/config', '/api/market/storage', '/api/storage/config'} and request.method == 'POST':
            if SAMBA_PENDING.exists() or DOMAIN_REMOVE_PENDING.exists() or _active(main, 'control-center-samba-apply.service') or _active(main, 'control-center-domain-destroy.service'):
                return jsonify(ok=False, error='Операции DNS/Сетевого хранилища заблокированы на время изменения Домена.'), 409
        return None

    app.before_request_funcs.setdefault(None, []).insert(0, dependency_request_guard_111)
