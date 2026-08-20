from __future__ import annotations

import ipaddress

from flask import jsonify, request

import release_110


def _active_module(main):
    module = main._read_json('/var/lib/control-center-system/modules/samba.json', {})
    return module if module.get('managed') and module.get('state') == 'active' else {}


def register(app, main):
    previous_hostname = app.view_functions.get('hostname_settings_110')
    previous_network = app.view_functions.get('network_config')
    previous_dhcp = app.view_functions.get('dhcp_config')

    if previous_hostname:
        def hostname_guard_111():
            module = _active_module(main)
            if request.method == 'POST' and module:
                return jsonify(
                    ok=False,
                    error=f"Нельзя переименовать активный контроллер домена {module.get('fqdn') or module.get('realm')}. Переименование DC требует отдельной процедуры миграции AD.",
                ), 409
            return previous_hostname()
        app.view_functions['hostname_settings_110'] = hostname_guard_111

    if previous_network:
        def network_guard_111():
            module = _active_module(main)
            if request.method == 'POST' and module:
                body = request.get_json(silent=True) or {}
                try:
                    validated = release_110._validate_network_110(main, body)
                except ValueError as exc:
                    return jsonify(ok=False, error=str(exc)), 400
                role = str(module.get('network_role') or '').lower()
                dc = validated.get(role) or {}
                try:
                    prefix = int(dc.get('mask'))
                except Exception:
                    prefix = -1
                if (
                    not dc.get('enabled')
                    or dc.get('method') != 'static'
                    or dc.get('interface') != module.get('interface')
                    or str(dc.get('ip') or '') != str(module.get('ipv4') or '')
                    or prefix != int(module.get('prefix') or -2)
                ):
                    return jsonify(
                        ok=False,
                        error=(
                            f"Сетевая роль {role.upper()} используется активным Samba AD-DC. "
                            f"Нельзя отключить роль, сменить интерфейс или адрес {module.get('ipv4')}/{module.get('prefix')} "
                            "без отдельной процедуры миграции контроллера домена."
                        ),
                    ), 409
            return previous_network()
        app.view_functions['network_config'] = network_guard_111

    if previous_dhcp:
        def dhcp_guard_111():
            module = _active_module(main)
            if request.method == 'POST' and module:
                body = request.get_json(silent=True) or {}
                if str(body.get('interface') or '') == str(module.get('interface') or ''):
                    raw_dns = body.get('dns') or []
                    if isinstance(raw_dns, str):
                        raw_dns = [x.strip() for x in raw_dns.replace(';', ',').split(',') if x.strip()]
                    clean = []
                    try:
                        clean = [str(ipaddress.IPv4Address(str(x))) for x in raw_dns]
                    except Exception:
                        pass
                    required = str(module.get('ipv4') or '')
                    if clean != [required]:
                        return jsonify(
                            ok=False,
                            error=(
                                f"DHCP на интерфейсе Samba AD-DC должен выдавать единственный DNS {required}. "
                                "Внешние DNS используются Samba как forwarder и не должны раздаваться доменным клиентам напрямую."
                            ),
                        ), 409
            return previous_dhcp()
        app.view_functions['dhcp_config'] = dhcp_guard_111
