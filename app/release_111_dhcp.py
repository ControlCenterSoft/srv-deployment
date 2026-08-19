from __future__ import annotations

import ipaddress
import re
import time
from pathlib import Path

from flask import jsonify, request

RESERVATIONS = Path('/var/lib/control-center-system/dhcp-reservations.json')
PENDING = Path('/var/lib/control-center/dhcp-reservations-pending.json')
CONFIG = Path('/var/lib/control-center-system/dhcp-config.json')
SAMBA = Path('/var/lib/control-center-system/modules/samba.json')


def _reservations(main):
    data = main._read_json(RESERVATIONS, {})
    return [x for x in (data.get('reservations') or []) if isinstance(x, dict)]


def _leases(service_module):
    return service_module._leases()


def register(app, main):
    # release_111_services owns the GET client aggregation. Replace only the
    # mutation endpoint with stricter subnet/conflict validation.
    service_module = __import__('release_111_services')

    def dhcp_reservations_strict_111():
        if not main._dhcp_installed():
            return jsonify(ok=False, error='DHCP Server не установлен'), 404
        if PENDING.exists():
            return jsonify(ok=False, error='Предыдущее изменение DHCP-бронирований ещё применяется'), 409
        cfg = main._read_json(CONFIG, {})
        try:
            start = ipaddress.IPv4Address(str(cfg['range_start']))
            prefix = int(cfg['mask'])
            network = ipaddress.IPv4Network(f'{start}/{prefix}', strict=False)
            gateway = ipaddress.IPv4Address(str(cfg['gateway']))
            interface = str(cfg['interface'])
        except Exception:
            return jsonify(ok=False, error='Сначала примените корректную конфигурацию DHCP'), 409

        body = request.get_json(silent=True) or {}
        action = str(body.get('action') or 'reserve').lower()
        mac = str(body.get('mac') or '').strip().lower()
        if not re.fullmatch(r'(?:[0-9a-f]{2}:){5}[0-9a-f]{2}', mac):
            return jsonify(ok=False, error='Некорректный MAC-адрес'), 400
        current = [x for x in _reservations(main) if str(x.get('mac') or '').lower() != mac]

        if action == 'release':
            payload = {'reservations': current, 'requested_at': int(time.time())}
        elif action == 'reserve':
            try:
                addr = ipaddress.IPv4Address(str(body.get('ip') or '').strip())
            except Exception:
                return jsonify(ok=False, error='Некорректный IPv4 для бронирования'), 400
            if addr not in network or addr in {network.network_address, network.broadcast_address, gateway}:
                return jsonify(ok=False, error=f'IP должен находиться в DHCP-подсети {network} и не совпадать с network/broadcast/gateway'), 400
            hostname = str(body.get('hostname') or '').strip()
            if len(hostname) > 63 or (hostname and not re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9.-]{0,61}[A-Za-z0-9])?', hostname)):
                return jsonify(ok=False, error='Некорректное имя DHCP-клиента'), 400
            if any(str(x.get('ip') or '') == str(addr) for x in current):
                return jsonify(ok=False, error='Этот IP уже забронирован другим MAC'), 409

            domain = main._read_json(SAMBA, {})
            if domain.get('managed') and domain.get('state') == 'active' and interface == domain.get('interface') and str(addr) == str(domain.get('ipv4')):
                return jsonify(ok=False, error='IP активного контроллера домена нельзя назначить DHCP-клиенту'), 409

            conflicts = []
            for lease in _leases(service_module):
                if lease.get('mac') != mac and lease.get('ip') == str(addr) and (lease.get('expiry') == 0 or int(lease.get('expiry') or 0) > int(time.time())):
                    conflicts.append(lease.get('mac'))
            if conflicts:
                return jsonify(ok=False, error=f'IP {addr} сейчас выдан другому клиенту: {", ".join(conflicts)}. Освободите аренду или выберите другой адрес.'), 409

            current.append({'mac': mac, 'ip': str(addr), 'hostname': hostname})
            payload = {'reservations': current, 'requested_at': int(time.time())}
        else:
            return jsonify(ok=False, error='action must be reserve or release'), 400

        main._write_json(PENDING, payload)
        return jsonify(ok=True, status='pending', message='DHCP-бронирование передано на применение. Новый адрес вступит в силу после DHCP renew клиента.'), 202

    app.view_functions['dhcp_reservations_111'] = dhcp_reservations_strict_111
