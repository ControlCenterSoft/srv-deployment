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
        lines = ROUTE_FILE.read_text(
            encoding="utf-8",
            errors="replace",
        ).splitlines()

        candidates = []

        for line in lines[1:]:
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

            gateway = socket.inet_ntoa(
                struct.pack(
                    "<L",
                    int(gateway_hex, 16),
                )
            )

            candidates.append(
                {
                    "interface": interface,
                    "gateway": gateway,
                    "metric": int(metric_text),
                }
            )

        if not candidates:
            return None

        candidates.sort(
            key=lambda item: item["metric"]
        )

        return candidates[0]

    except Exception:
        return None


def _dns_servers() -> list[str]:
    servers: list[str] = []

    try:
        for line in RESOLV_CONF.read_text(
            encoding="utf-8",
            errors="replace",
        ).splitlines():
            stripped = line.strip()

            if not stripped.startswith("nameserver "):
                continue

            value = stripped.split(
                None,
                1,
            )[1].strip()

            try:
                ip_address(value)
            except ValueError:
                continue

            if value not in servers:
                servers.append(value)

    except Exception:
        pass

    return servers


def _interface_role(
    name: str,
    ipv4_addresses: list[str],
    default_interface: str | None,
) -> str:
    if name == "lo":
        return "loopback"

    if name == default_interface:
        return "default-route"

    private = False

    for value in ipv4_addresses:
        try:
            private = private or ip_address(
                value
            ).is_private
        except ValueError:
            pass

    if private:
        return "lan-candidate"

    return "unclassified"


def snapshot() -> dict:
    addresses = psutil.net_if_addrs()
    stats = psutil.net_if_stats()
    counters = psutil.net_io_counters(
        pernic=True
    )

    default_route = _ipv4_default_route()
    default_interface = (
        default_route.get("interface")
        if default_route
        else None
    )

    interfaces = []

    for name in sorted(addresses):
        ipv4_addresses: list[str] = []
        ipv6_addresses: list[str] = []
        mac_addresses: list[str] = []

        for item in addresses.get(
            name,
            [],
        ):
            if item.family == socket.AF_INET:
                ipv4_addresses.append(
                    item.address
                )
            elif item.family == socket.AF_INET6:
                ipv6_addresses.append(
                    item.address.split(
                        "%",
                        1,
                    )[0]
                )
            elif getattr(
                psutil,
                "AF_LINK",
                object(),
            ) == item.family:
                mac_addresses.append(
                    item.address
                )

        state = stats.get(name)
        traffic = counters.get(name)

        interface = {
            "name": name,
            "role": _interface_role(
                name,
                ipv4_addresses,
                default_interface,
            ),
            "is_up": (
                bool(state.isup)
                if state
                else False
            ),
            "speed_mbps": (
                int(state.speed)
                if state
                else 0
            ),
            "mtu": (
                int(state.mtu)
                if state
                else 0
            ),
            "ipv4": ipv4_addresses,
            "ipv6": ipv6_addresses,
            "mac": (
                mac_addresses[0]
                if mac_addresses
                else None
            ),
            "traffic": {
                "bytes_sent": (
                    int(traffic.bytes_sent)
                    if traffic
                    else 0
                ),
                "bytes_recv": (
                    int(traffic.bytes_recv)
                    if traffic
                    else 0
                ),
                "packets_sent": (
                    int(traffic.packets_sent)
                    if traffic
                    else 0
                ),
                "packets_recv": (
                    int(traffic.packets_recv)
                    if traffic
                    else 0
                ),
                "errors_in": (
                    int(traffic.errin)
                    if traffic
                    else 0
                ),
                "errors_out": (
                    int(traffic.errout)
                    if traffic
                    else 0
                ),
                "drops_in": (
                    int(traffic.dropin)
                    if traffic
                    else 0
                ),
                "drops_out": (
                    int(traffic.dropout)
                    if traffic
                    else 0
                ),
            },
        }

        interfaces.append(interface)

    lan_candidates = [
        item["name"]
        for item in interfaces
        if item["role"] == "lan-candidate"
    ]

    vpn_prefixes = (
        "tun",
        "tap",
        "wg",
        "ppp",
        "tailscale",
        "zt",
        "awg",
    )

    vpn_interfaces = [
        item["name"]
        for item in interfaces
        if item["name"].lower().startswith(
            vpn_prefixes
        )
    ]

    return {
        "default_route": default_route,
        "wan_candidate": default_interface,
        "lan_candidates": lan_candidates,
        "vpn_interfaces": vpn_interfaces,
        "dns_servers": _dns_servers(),
        "interfaces": interfaces,
    }
