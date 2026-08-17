from __future__ import annotations

from ipaddress import ip_address
from pathlib import Path
import socket
import struct

import psutil


ROUTE_FILE = Path("/proc/net/route")
RESOLV_CONF = Path("/etc/resolv.conf")


def _ipv4_default_route() -> dict | None:
    try:
        lines = ROUTE_FILE.read_text(encoding="utf-8", errors="replace").splitlines()
    except Exception:
        return None

    candidates: list[dict] = []
    for line in lines[1:]:
        try:
            fields = line.split()
            if len(fields) < 11:
                continue
            interface = fields[0]
            destination = fields[1]
            gateway_hex = fields[2]
            flags_hex = fields[3]
            metric_text = fields[6]
            if destination != "00000000":
                continue
            flags = int(flags_hex, 16)
            if not flags & 0x1:
                continue
            gateway = socket.inet_ntoa(struct.pack("<L", int(gateway_hex, 16)))
            candidates.append(
                {
                    "interface": interface,
                    "gateway": gateway,
                    "metric": int(metric_text),
                }
            )
        except Exception:
            continue

    if not candidates:
        return None
    candidates.sort(key=lambda item: item.get("metric", 0))
    return candidates[0]


def _dns_servers() -> list[str]:
    servers: list[str] = []
    try:
        lines = RESOLV_CONF.read_text(encoding="utf-8", errors="replace").splitlines()
    except Exception:
        return servers

    for line in lines:
        stripped = line.strip()
        if not stripped.startswith("nameserver "):
            continue
        try:
            value = stripped.split(None, 1)[1].strip()
            ip_address(value)
        except Exception:
            continue
        if value not in servers:
            servers.append(value)
    return servers


def _prefix_from_netmask(netmask: str | None) -> int | None:
    if not netmask:
        return None
    try:
        packed = socket.inet_aton(netmask)
        bits = "".join(f"{byte:08b}" for byte in packed)
        if "01" in bits:
            return None
        return bits.count("1")
    except Exception:
        return None


def _interface_role(name: str, ipv4_addresses: list[str], default_interface: str | None) -> str:
    if name == "lo":
        return "loopback"
    if name == default_interface:
        return "default-route"
    for value in ipv4_addresses:
        try:
            if ip_address(value).is_private:
                return "lan-candidate"
        except ValueError:
            continue
    return "unclassified"


def _collect(callable_, fallback, label: str, warnings: list[str]):
    try:
        value = callable_()
        return value if value is not None else fallback
    except Exception as exc:
        warnings.append(f"{label}: {type(exc).__name__}: {str(exc)[:160]}")
        return fallback


def _int_value(value) -> int:
    try:
        return int(value or 0)
    except Exception:
        return 0


def _traffic_value(traffic, name: str) -> int:
    if traffic is None:
        return 0
    return _int_value(getattr(traffic, name, 0))


def snapshot() -> dict:
    warnings: list[str] = []
    addresses = _collect(psutil.net_if_addrs, {}, "net_if_addrs", warnings)
    stats = _collect(psutil.net_if_stats, {}, "net_if_stats", warnings)
    counters = _collect(lambda: psutil.net_io_counters(pernic=True), {}, "net_io_counters", warnings)

    default_route = _ipv4_default_route()
    default_interface = default_route.get("interface") if default_route else None

    names = sorted(set(addresses) | set(stats) | set(counters))
    interfaces: list[dict] = []

    link_families = {
        value
        for value in (
            getattr(psutil, "AF_LINK", None),
            getattr(socket, "AF_PACKET", None),
        )
        if value is not None
    }

    for name in names:
        ipv4_addresses: list[str] = []
        ipv4_details: list[dict] = []
        ipv6_addresses: list[str] = []
        mac_addresses: list[str] = []

        for item in addresses.get(name, []) or []:
            try:
                if item.family == socket.AF_INET:
                    ipv4_addresses.append(item.address)
                    ipv4_details.append(
                        {
                            "address": item.address,
                            "netmask": item.netmask,
                            "prefix": _prefix_from_netmask(item.netmask),
                            "broadcast": item.broadcast,
                        }
                    )
                elif item.family == socket.AF_INET6:
                    ipv6_addresses.append(str(item.address).split("%", 1)[0])
                elif item.family in link_families:
                    if item.address:
                        mac_addresses.append(str(item.address))
            except Exception as exc:
                warnings.append(f"interface {name}: {type(exc).__name__}: {str(exc)[:120]}")

        state = stats.get(name)
        traffic = counters.get(name)
        interfaces.append(
            {
                "name": name,
                "role": _interface_role(name, ipv4_addresses, default_interface),
                "is_up": bool(getattr(state, "isup", False)) if state else False,
                "speed_mbps": _int_value(getattr(state, "speed", 0)) if state else 0,
                "mtu": _int_value(getattr(state, "mtu", 0)) if state else 0,
                "ipv4": ipv4_addresses,
                "ipv4_details": ipv4_details,
                "ipv6": ipv6_addresses,
                "mac": mac_addresses[0] if mac_addresses else None,
                "traffic": {
                    "bytes_sent": _traffic_value(traffic, "bytes_sent"),
                    "bytes_recv": _traffic_value(traffic, "bytes_recv"),
                    "packets_sent": _traffic_value(traffic, "packets_sent"),
                    "packets_recv": _traffic_value(traffic, "packets_recv"),
                    "errors_in": _traffic_value(traffic, "errin"),
                    "errors_out": _traffic_value(traffic, "errout"),
                    "drops_in": _traffic_value(traffic, "dropin"),
                    "drops_out": _traffic_value(traffic, "dropout"),
                },
            }
        )

    lan_candidates = [item["name"] for item in interfaces if item["role"] == "lan-candidate"]
    vpn_prefixes = ("tun", "tap", "wg", "ppp", "tailscale", "zt", "awg")
    vpn_interfaces = [
        item["name"]
        for item in interfaces
        if str(item["name"]).lower().startswith(vpn_prefixes)
    ]

    return {
        "default_route": default_route,
        "wan_candidate": default_interface,
        "lan_candidates": lan_candidates,
        "vpn_interfaces": vpn_interfaces,
        "dns_servers": _dns_servers(),
        "interfaces": interfaces,
        "warnings": warnings,
    }
