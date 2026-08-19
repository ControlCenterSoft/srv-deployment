from __future__ import annotations

import hashlib
import ipaddress
import json
import re
import time
from pathlib import Path

from flask import jsonify, request

DNS_MODULE = Path('/var/lib/control-center-system/modules/dns.json')
DNS_PENDING = Path('/var/lib/control-center/dns-pending.json')
DNS_STATUS = Path('/var/lib/control-center-system/dns-status.json')
STORAGE_MODULE = Path('/var/lib/control-center-system/modules/storage.json')
STORAGE_PENDING = Path('/var/lib/control-center/storage-pending.json')
STORAGE_STATUS = Path('/var/lib/control-center-system/storage-status.json')
SAMBA_MODULE = Path('/var/lib/control-center-system/modules/samba.json')
SAMBA_STATUS = Path('/var/lib/control-center-system/samba-status.json')
DOMAIN_REMOVE_PENDING = Path('/run/control-center/domain-remove.json')
DHCP_RESERVATIONS = Path('/var/lib/control-center-system/dhcp-reservations.json')
DHCP_RESERVATIONS_PENDING = Path('/var/lib/control-center/dhcp-reservations-pending.json')
DHCP_RESERVATIONS_STATUS = Path('/var/lib/control-center-system/dhcp-reservations-status.json')
CLEANUP_DIR = Path('/var/lib/control-center-system/cleanup-audits')


def _service(main, unit):
    rc, out, _ = main._run(['systemctl', 'is-active', unit], 4)
    return {'unit': unit, 'active': rc == 0 and out.strip() == 'active', 'state': out.strip() or 'inactive'}


def _domain(main):
    m = main._read_json(SAMBA_MODULE, {})
    return m if m.get('managed') and m.get('state') == 'active' else {}


def _module_status(main, module_path, status_path, unit, dependency=None):
    m = main._read_json(module_path, {})
    s = main._read_json(status_path, {})
    service = _service(main, unit) if m.get('installed') else {'unit': unit, 'active': False, 'state': 'inactive'}
    installed = bool(m.get('installed'))
    code = 'available'
    label = 'Не установлен'
    detail = 'Сервис доступен для установки.'
    state = str(s.get('state') or '')
    if state in {'installing', 'removing', 'applying', 'configuring'}:
        code = 'removing' if state == 'removing' else 'installing'
        label = 'Удаление…' if state == 'removing' else 'Применение…'
        detail = s.get('message') or state
    elif state in {'error', 'rollback', 'failed', 'rejected'}:
        code = 'error'; label = 'Ошибка'; detail = s.get('detail') or s.get('message') or state
    elif installed:
        code = 'running' if service['active'] else 'error'
        label = 'Работает' if service['active'] else 'Ошибка'
        detail = f"{m.get('provider') or m.get('mode') or unit}" if service['active'] else f"{unit}: {service['state']}"
    if dependency and installed:
        detail += f" · зависимость: {dependency}"
    return {'module': m, 'status': s, 'service': service, 'market': {'code': code, 'label': label, 'detail': detail, 'timestamp': int(s.get('timestamp') or m.get('installed_at') or 0)}}


def _dns(main):
    domain = _domain(main)
    if domain:
        m = main._read_json(DNS_MODULE, {})
        if not m:
            m = {'installed': True, 'provider': 'samba_internal', 'explicit': False, 'dependency_by': ['domain'], 'forwarders': [domain.get('dns_forwarder')] if domain.get('dns_forwarder') else []}
        s = main._read_json(DNS_STATUS, {})
        svc = _service(main, 'samba-ad-dc.service')
        return {'module': m, 'status': s, 'service': svc, 'market': {'code': 'running' if svc['active'] else 'error', 'label': 'Работает' if svc['active'] else 'Ошибка', 'detail': f"Samba Internal DNS · {domain.get('ipv4','')}" if svc['active'] else 'Samba AD-DC DNS не работает', 'timestamp': int(domain.get('provisioned_at') or 0)}}
    return _module_status(main, DNS_MODULE, DNS_STATUS, 'unbound.service')


def _storage(main):
    domain = _domain(main)
    if domain:
        m = main._read_json(STORAGE_MODULE, {})
        if not m:
            m = {'installed': True, 'provider': 'samba_ad_dc', 'explicit': False, 'dependency_by': ['domain'], 'share_name': 'Public', 'path': '/srv/control-center/storage/public'}
        s = main._read_json(STORAGE_STATUS, {})
        svc = _service(main, 'samba-ad-dc.service')
        return {'module': m, 'status': s, 'service': svc, 'market': {'code': 'running' if svc['active'] else 'error', 'label': 'Работает' if svc['active'] else 'Ошибка', 'detail': f"SMB · {m.get('share_name','Public')} · доменная авторизация" if svc['active'] else 'Samba AD-DC SMB не работает', 'timestamp': int(domain.get('provisioned_at') or 0)}}
    return _module_status(main, STORAGE_MODULE, STORAGE_STATUS, 'smbd.service')


def _domain_market(main):
    m = main._read_json(SAMBA_MODULE, {})
    s = main._read_json(SAMBA_STATUS, {})
    state = str(s.get('state') or '')
    if state in {'provisioning', 'installing', 'applying'}:
        return {'code': 'installing', 'label': 'Установка…', 'detail': s.get('message') or 'Создание домена выполняется', 'timestamp': int(s.get('timestamp') or time.time())}
    if state in {'removing', 'destroying'}:
        return {'code': 'removing', 'label': 'Удаление…', 'detail': s.get('message') or 'Удаление домена выполняется', 'timestamp': int(s.get('timestamp') or time.time())}
    if state in {'error', 'rollback', 'failed', 'rejected'} and not (m.get('managed') and m.get('state') == 'active'):
        return {'code': 'error', 'label': 'Ошибка', 'detail': s.get('detail') or s.get('message') or state, 'timestamp': int(s.get('timestamp') or 0)}
    if m.get('managed') and m.get('state') == 'active':
        svc = _service(main, 'samba-ad-dc.service')
        return {'code': 'running' if svc['active'] else 'error', 'label': 'Работает' if svc['active'] else 'Ошибка', 'detail': f"{m.get('realm','')} · {m.get('fqdn','')}" if svc['active'] else 'samba-ad-dc.service не активен', 'timestamp': int(m.get('provisioned_at') or 0)}
    return {'code': 'available', 'label': 'Не установлен', 'detail': 'Установка нового домена через мастер первоначальной настройки.', 'timestamp': 0}


def _validate_forwarders(raw):
    if isinstance(raw, str):
        raw = [x.strip() for x in raw.replace(';', ',').split(',') if x.strip()]
    if not isinstance(raw, list) or not raw:
        raise ValueError('Укажите хотя бы один DNS forwarder')
    out = []
    for item in raw[:4]:
        try:
            ip = ipaddress.IPv4Address(str(item).strip())
        except Exception:
            raise ValueError(f'Некорректный DNS forwarder: {item}')
        if ip.is_loopback or ip.is_multicast or ip.is_unspecified:
            raise ValueError(f'Недопустимый DNS forwarder: {ip}')
        if str(ip) not in out:
            out.append(str(ip))
    return out


def _validate_share_name(value):
    value = str(value or '').strip()
    if not re.fullmatch(r'[A-Za-zА-Яа-яЁё0-9][A-Za-zА-Яа-яЁё0-9 _.-]{0,31}', value):
        raise ValueError('Имя SMB-ресурса: 1–32 символа, буквы/цифры/пробел/._-')
    return value


def _leases():
    candidates = [Path('/var/lib/misc/dnsmasq.leases'), Path('/var/lib/control-center-system/dhcp.leases')]
    rows = []
    for path in candidates:
        if not path.exists():
            continue
        try:
            lines = path.read_text(errors='replace').splitlines()
        except Exception:
            continue
        for line in lines:
            parts = line.split()
            if len(parts) < 4:
                continue
            try:
                expiry = int(parts[0])
                mac = parts[1].lower()
                ipaddress.IPv4Address(parts[2])
            except Exception:
                continue
            rows.append({'expiry': expiry, 'mac': mac, 'ip': parts[2], 'hostname': '' if parts[3] == '*' else parts[3], 'client_id': parts[4] if len(parts) > 4 and parts[4] != '*' else ''})
        if rows:
            break
    return rows


def _reservations(main):
    data = main._read_json(DHCP_RESERVATIONS, {})
    items = data.get('reservations') if isinstance(data.get('reservations'), list) else []
    return items


def register(app, main):
    previous_market = app.view_functions.get('market')

    def market_services_111():
        try:
            payload = previous_market().get_json() if previous_market else {'items': []}
        except Exception:
            payload = {'items': []}
        items = [x for x in (payload.get('items') or []) if x.get('id') not in {'samba', 'domain', 'dns', 'storage'}]
        domain_installed = bool(_domain(main))
        dns = _dns(main); storage = _storage(main)
        items.extend([
            {'id': 'domain', 'name': 'Домен', 'description': 'Samba Active Directory Domain Controller', 'state': 'installed' if domain_installed else 'available', 'installable': True, 'action_mode': 'wizard', 'status': _domain_market(main), 'dependencies': ['dns', 'storage']},
            {'id': 'dns', 'name': 'DNS', 'description': 'DNS-сервер: standalone Unbound или Samba Internal DNS', 'state': 'installed' if dns['module'].get('installed') or domain_installed else 'available', 'installable': True, 'status': dns['market'], 'required_by': ['domain'] if domain_installed else []},
            {'id': 'storage', 'name': 'Сетевое хранилище', 'description': 'SMB-хранилище. Может работать отдельно; обязательно для Домена.', 'state': 'installed' if storage['module'].get('installed') or domain_installed else 'available', 'installable': True, 'status': storage['market'], 'required_by': ['domain'] if domain_installed else []},
        ])
        payload['items'] = items
        payload.update(domain_installed=domain_installed, dns_installed=bool(dns['module'].get('installed') or domain_installed), storage_installed=bool(storage['module'].get('installed') or domain_installed))
        return jsonify(payload)

    app.view_functions['market'] = market_services_111

    @app.post('/api/market/dns')
    def market_dns_111():
        body = request.get_json(silent=True) or {}
        action = str(body.get('action') or '').lower()
        if action not in {'install', 'remove'}:
            return jsonify(ok=False, error='action must be install or remove'), 400
        if action == 'remove' and _domain(main):
            return jsonify(ok=False, error='DNS нельзя удалить, пока активен Домен. DNS является обязательной зависимостью доменной службы.'), 409
        if DNS_PENDING.exists():
            return jsonify(ok=False, error='Операция DNS уже выполняется'), 409
        main._write_json(DNS_PENDING, {'action': action, 'explicit': True, 'requested_at': int(time.time())})
        return jsonify(ok=True, status='pending', message='Операция DNS передана root worker'), 202

    @app.route('/api/dns/config', methods=['GET', 'POST'])
    def dns_config_111():
        state = _dns(main)
        if request.method == 'POST':
            if not (state['module'].get('installed') or _domain(main)):
                return jsonify(ok=False, error='DNS не установлен'), 404
            body = request.get_json(silent=True) or {}
            try:
                forwarders = _validate_forwarders(body.get('forwarders'))
            except ValueError as exc:
                return jsonify(ok=False, error=str(exc)), 400
            main._write_json(DNS_PENDING, {'action': 'configure', 'forwarders': forwarders, 'requested_at': int(time.time())})
            return jsonify(ok=True, status='pending', message='DNS-настройки переданы на применение'), 202
        return jsonify(provider=state['module'].get('provider'), config=state['module'], status=state['status'], service=state['service'], domain_active=bool(_domain(main)))

    @app.post('/api/market/storage')
    def market_storage_111():
        body = request.get_json(silent=True) or {}
        action = str(body.get('action') or '').lower()
        if action not in {'install', 'remove'}:
            return jsonify(ok=False, error='action must be install or remove'), 400
        if action == 'remove' and _domain(main):
            return jsonify(ok=False, error='Сетевое хранилище нельзя удалить, пока активен Домен. Домен без SMB-хранилища не поддерживается.'), 409
        if STORAGE_PENDING.exists():
            return jsonify(ok=False, error='Операция сетевого хранилища уже выполняется'), 409
        main._write_json(STORAGE_PENDING, {'action': action, 'explicit': True, 'requested_at': int(time.time())})
        return jsonify(ok=True, status='pending', message='Операция сетевого хранилища передана root worker'), 202

    @app.route('/api/storage/config', methods=['GET', 'POST'])
    def storage_config_111():
        state = _storage(main)
        if request.method == 'POST':
            if not (state['module'].get('installed') or _domain(main)):
                return jsonify(ok=False, error='Сетевое хранилище не установлено'), 404
            body = request.get_json(silent=True) or {}
            try:
                share_name = _validate_share_name(body.get('share_name') or 'Public')
            except ValueError as exc:
                return jsonify(ok=False, error=str(exc)), 400
            main._write_json(STORAGE_PENDING, {'action': 'configure', 'share_name': share_name, 'requested_at': int(time.time())})
            return jsonify(ok=True, status='pending', message='Настройки SMB-хранилища переданы на применение'), 202
        return jsonify(config=state['module'], status=state['status'], service=state['service'], domain_active=bool(_domain(main)), rbac_ready=True)

    @app.post('/api/domain/remove')
    def domain_remove_111():
        module = _domain(main)
        if not module:
            return jsonify(ok=False, error='Домен не установлен'), 404
        if DOMAIN_REMOVE_PENDING.exists():
            return jsonify(ok=False, error='Удаление домена уже ожидает root worker'), 409
        body = request.get_json(silent=True) or {}
        code = str(body.get('approval_code') or '').strip().lower()
        phrase = str(body.get('confirmation') or '').strip()
        if not re.fullmatch(r'[0-9a-f]{8}', code):
            return jsonify(ok=False, error='Введите одноразовый код из sudo control-center-samba-approve --remove'), 400
        if phrase != 'УДАЛИТЬ ДОМЕН':
            return jsonify(ok=False, error='Для удаления введите подтверждение: УДАЛИТЬ ДОМЕН'), 400
        main._write_json(DOMAIN_REMOVE_PENDING, {'approval_code': code, 'requested_at': int(time.time()), 'realm': module.get('realm'), 'fqdn': module.get('fqdn')})
        return jsonify(ok=True, status='pending', message='Удаление домена передано root worker. Перед удалением будет создан полный backup и выполнена проверка на дополнительные DC.'), 202

    @app.get('/api/services/cleanup/audits')
    def cleanup_audits_111():
        rows = []
        try:
            for p in sorted(CLEANUP_DIR.glob('*.json'), key=lambda x: x.stat().st_mtime, reverse=True)[:30]:
                try:
                    d = json.loads(p.read_text())
                    if isinstance(d, dict):
                        d['file'] = p.name; rows.append(d)
                except Exception:
                    pass
        except Exception:
            pass
        return jsonify(items=rows, count=len(rows))

    @app.get('/api/dhcp/clients')
    def dhcp_clients_111():
        reservations = _reservations(main)
        by_mac = {str(x.get('mac') or '').lower(): x for x in reservations if isinstance(x, dict)}
        now = int(time.time())
        rows = []
        seen = set()
        for lease in _leases():
            r = by_mac.get(lease['mac']) or {}
            rows.append({**lease, 'online': lease['expiry'] == 0 or lease['expiry'] > now, 'reserved': bool(r), 'reserved_ip': r.get('ip') or '', 'reservation_hostname': r.get('hostname') or ''})
            seen.add(lease['mac'])
        for mac, r in by_mac.items():
            if mac in seen:
                continue
            rows.append({'expiry': 0, 'mac': mac, 'ip': r.get('ip') or '', 'hostname': r.get('hostname') or '', 'client_id': '', 'online': False, 'reserved': True, 'reserved_ip': r.get('ip') or '', 'reservation_hostname': r.get('hostname') or ''})
        rows.sort(key=lambda x: (not x['online'], x.get('hostname') or '', x['mac']))
        return jsonify(items=rows, count=len(rows), reservations=reservations, status=main._read_json(DHCP_RESERVATIONS_STATUS, {}))

    @app.post('/api/dhcp/reservations')
    def dhcp_reservations_111():
        if not main._dhcp_installed():
            return jsonify(ok=False, error='DHCP Server не установлен'), 404
        body = request.get_json(silent=True) or {}
        action = str(body.get('action') or 'reserve').lower()
        mac = str(body.get('mac') or '').strip().lower()
        if not re.fullmatch(r'(?:[0-9a-f]{2}:){5}[0-9a-f]{2}', mac):
            return jsonify(ok=False, error='Некорректный MAC-адрес'), 400
        current = _reservations(main)
        current = [x for x in current if isinstance(x, dict) and str(x.get('mac') or '').lower() != mac]
        if action == 'release':
            payload = {'reservations': current, 'requested_at': int(time.time())}
        elif action == 'reserve':
            try:
                ip = str(ipaddress.IPv4Address(str(body.get('ip') or '').strip()))
            except Exception:
                return jsonify(ok=False, error='Некорректный IPv4 для бронирования'), 400
            hostname = str(body.get('hostname') or '').strip()
            if len(hostname) > 63 or (hostname and not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9.-]{0,62}', hostname)):
                return jsonify(ok=False, error='Некорректное имя DHCP-клиента'), 400
            if any(str(x.get('ip') or '') == ip for x in current):
                return jsonify(ok=False, error='Этот IP уже забронирован другим MAC'), 409
            current.append({'mac': mac, 'ip': ip, 'hostname': hostname})
            payload = {'reservations': current, 'requested_at': int(time.time())}
        else:
            return jsonify(ok=False, error='action must be reserve or release'), 400
        main._write_json(DHCP_RESERVATIONS_PENDING, payload)
        return jsonify(ok=True, status='pending', message='DHCP-бронирование передано на применение. Клиент получит новый IP при следующем DHCP renew.'), 202
