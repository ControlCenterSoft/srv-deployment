from __future__ import annotations

from ipaddress import IPv4Address, IPv4Interface, IPv4Network, ip_address


SUPPORTED_WAN_MODES = ("dhcp",)
SUPPORTED_DNS_MODES = ("automatic", "custom")


def capabilities() -> dict:
    return {
        "wan_modes": list(SUPPORTED_WAN_MODES),
        "dns_modes": list(SUPPORTED_DNS_MODES),
        "apply_enabled": False,
        "planning_only": True,
    }


def _string(value) -> str:
    return str(value or "").strip()


def _validate_interface(
    name: str,
    available: set[str],
    field: str,
    errors: list[str],
) -> None:
    if not name:
        errors.append(f"{field}: interface is required")
        return
    if name not in available:
        errors.append(f"{field}: interface {name!r} is not present on this server")


def _parse_lan(value: str, errors: list[str]) -> IPv4Interface | None:
    if not value:
        errors.append("lan_address: IPv4 address with prefix is required")
        return None
    try:
        interface = IPv4Interface(value)
    except ValueError:
        errors.append("lan_address: use IPv4 CIDR format, for example 192.168.10.1/24")
        return None
    if not interface.ip.is_private:
        errors.append("lan_address: LAN address must be from a private IPv4 range")
    if interface.network.prefixlen < 16 or interface.network.prefixlen > 30:
        errors.append("lan_address: supported LAN prefix length is /16 through /30")
    if interface.ip in (
        interface.network.network_address,
        interface.network.broadcast_address,
    ):
        errors.append("lan_address: server address cannot be network or broadcast address")
    return interface


def _parse_pool_address(
    value: str,
    field: str,
    network: IPv4Network | None,
    server_ip: IPv4Address | None,
    errors: list[str],
) -> IPv4Address | None:
    if not value:
        errors.append(f"{field}: address is required while DHCP is enabled")
        return None
    try:
        parsed = ip_address(value)
    except ValueError:
        errors.append(f"{field}: invalid IPv4 address")
        return None
    if not isinstance(parsed, IPv4Address):
        errors.append(f"{field}: IPv4 address is required")
        return None
    if network is not None and parsed not in network:
        errors.append(f"{field}: address must be inside {network}")
    if network is not None and parsed in (
        network.network_address,
        network.broadcast_address,
    ):
        errors.append(f"{field}: network and broadcast addresses cannot be leased")
    if server_ip is not None and parsed == server_ip:
        errors.append(f"{field}: DHCP pool cannot contain the SRV LAN address")
    return parsed


def _parse_dns(values, errors: list[str]) -> list[str]:
    if not isinstance(values, list):
        errors.append("dns_servers: expected a list of IPv4 addresses")
        return []
    result: list[str] = []
    for item in values:
        value = _string(item)
        if not value:
            continue
        try:
            parsed = ip_address(value)
        except ValueError:
            errors.append(f"dns_servers: invalid address {value!r}")
            continue
        if not isinstance(parsed, IPv4Address):
            errors.append(f"dns_servers: IPv4 address required, got {value!r}")
            continue
        text = str(parsed)
        if text not in result:
            result.append(text)
    return result


def build_plan(payload: dict, current: dict) -> dict:
    errors: list[str] = []
    warnings: list[str] = []

    if not isinstance(payload, dict):
        return {
            "valid": False,
            "apply_enabled": False,
            "errors": ["request body must be a JSON object"],
            "warnings": [],
            "normalized": None,
            "steps": [],
            "rollback": [],
        }

    interfaces = current.get("interfaces", [])
    available = {
        str(item.get("name"))
        for item in interfaces
        if item.get("name")
    }

    wan_mode = _string(payload.get("wan_mode")).lower()
    wan_interface = _string(payload.get("wan_interface"))
    lan_interface = _string(payload.get("lan_interface"))
    lan_address_text = _string(payload.get("lan_address"))

    if wan_mode not in SUPPORTED_WAN_MODES:
        errors.append("wan_mode: expected dhcp")

    _validate_interface(wan_interface, available, "wan_interface", errors)
    _validate_interface(lan_interface, available, "lan_interface", errors)

    if wan_interface and lan_interface and wan_interface == lan_interface:
        errors.append("WAN and LAN interfaces must be different")

    lan_interface_value = _parse_lan(lan_address_text, errors)
    dhcp_enabled = bool(payload.get("dhcp_enabled", True))
    dhcp_start_text = _string(payload.get("dhcp_start"))
    dhcp_end_text = _string(payload.get("dhcp_end"))

    network = lan_interface_value.network if lan_interface_value else None
    server_ip = lan_interface_value.ip if lan_interface_value else None

    dhcp_start = None
    dhcp_end = None
    if dhcp_enabled:
        dhcp_start = _parse_pool_address(
            dhcp_start_text,
            "dhcp_start",
            network,
            server_ip,
            errors,
        )
        dhcp_end = _parse_pool_address(
            dhcp_end_text,
            "dhcp_end",
            network,
            server_ip,
            errors,
        )
        if dhcp_start is not None and dhcp_end is not None and int(dhcp_start) > int(dhcp_end):
            errors.append("DHCP pool start must not be greater than pool end")
        if (
            dhcp_start is not None
            and dhcp_end is not None
            and server_ip is not None
            and int(dhcp_start) <= int(server_ip) <= int(dhcp_end)
        ):
            errors.append("DHCP pool must not include the SRV LAN address")

    dns_mode = _string(payload.get("dns_mode", "automatic")).lower()
    if dns_mode not in SUPPORTED_DNS_MODES:
        errors.append("dns_mode: expected automatic or custom")

    dns_servers = _parse_dns(payload.get("dns_servers", []), errors)
    if dns_mode == "custom" and not dns_servers:
        errors.append("dns_servers: at least one DNS server is required in custom mode")

    current_default = current.get("wan_candidate")
    if current_default and wan_interface and current_default != wan_interface:
        warnings.append(
            "Selected WAN differs from the current default-route interface."
        )

    if lan_interface:
        item = next(
            (entry for entry in interfaces if entry.get("name") == lan_interface),
            None,
        )
        if item and item.get("role") == "default-route":
            errors.append(
                "The current default-route interface cannot be selected as LAN."
            )

    normalized = {
        "wan_mode": wan_mode,
        "wan_interface": wan_interface,
        "lan_interface": lan_interface,
        "lan_address": (
            str(lan_interface_value)
            if lan_interface_value
            else lan_address_text
        ),
        "dhcp_enabled": dhcp_enabled,
        "dhcp_start": str(dhcp_start) if dhcp_start else None,
        "dhcp_end": str(dhcp_end) if dhcp_end else None,
        "dns_mode": dns_mode,
        "dns_servers": dns_servers,
    }

    steps = [
        {
            "order": 1,
            "action": "inventory",
            "description": "Проверить наличие выбранных WAN/LAN интерфейсов и текущий маршрут по умолчанию.",
        },
        {
            "order": 2,
            "action": "address-validation",
            "description": "Проверить LAN CIDR, адрес SRV и границы DHCP-пула.",
        },
        {
            "order": 3,
            "action": "dns-validation",
            "description": "Проверить режим DNS и корректность заданных DNS-серверов.",
        },
    ]

    return {
        "valid": not errors,
        "apply_enabled": False,
        "errors": errors,
        "warnings": warnings,
        "normalized": normalized,
        "steps": steps,
        "rollback": [],
        "current_wan": current_default,
    }
