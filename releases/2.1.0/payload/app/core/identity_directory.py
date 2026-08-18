from __future__ import annotations

from pathlib import Path
import shutil
import subprocess

from app.core.system_auth import resolve_identity


ADMIN_GROUP_NAMES = {"root", "sudo", "wheel", "admin"}
LOGIN_SHELL_BLOCKLIST = {"/usr/sbin/nologin", "/sbin/nologin", "/bin/false", "/usr/bin/false"}


def _run(command: list[str], timeout: float = 8.0) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )


def _domain_users() -> list[str]:
    if shutil.which("wbinfo") is None:
        return []
    try:
        result = _run(["wbinfo", "-u"], timeout=12.0)
    except Exception:
        return []
    if result.returncode != 0:
        return []
    return sorted({line.strip() for line in result.stdout.splitlines() if line.strip()}, key=str.casefold)


def _domain_groups() -> list[str]:
    if shutil.which("wbinfo") is None:
        return []
    try:
        result = _run(["wbinfo", "-g"], timeout=12.0)
    except Exception:
        return []
    if result.returncode != 0:
        return []
    return sorted({line.strip() for line in result.stdout.splitlines() if line.strip()}, key=str.casefold)


def _local_users(domain_names: set[str]) -> list[dict]:
    try:
        result = _run(["getent", "passwd"], timeout=10.0)
    except Exception:
        return []
    if result.returncode != 0:
        return []

    items: list[dict] = []
    for line in result.stdout.splitlines():
        parts = line.split(":")
        if len(parts) < 7:
            continue
        name, uid_raw, gid_raw, gecos, home, shell = (
            parts[0], parts[2], parts[3], parts[4], parts[5], parts[6]
        )
        if name.casefold() in domain_names:
            continue
        try:
            uid = int(uid_raw)
            gid = int(gid_raw)
        except ValueError:
            continue
        if uid != 0 and (uid < 1000 or shell in LOGIN_SHELL_BLOCKLIST):
            continue
        identity = resolve_identity(name, "local")
        items.append(
            {
                "username": name,
                "uid": uid,
                "gid": gid,
                "display_name": gecos.split(",", 1)[0] or None,
                "home": home,
                "shell": shell,
                "source": "local",
                "is_admin": bool(identity and identity.is_admin),
            }
        )
    return sorted(items, key=lambda item: str(item["username"]).casefold())


def _local_groups(domain_names: set[str]) -> list[dict]:
    try:
        result = _run(["getent", "group"], timeout=10.0)
    except Exception:
        return []
    if result.returncode != 0:
        return []

    items: list[dict] = []
    for line in result.stdout.splitlines():
        parts = line.split(":")
        if len(parts) < 4:
            continue
        name, gid_raw, members_raw = parts[0], parts[2], parts[3]
        if name.casefold() in domain_names:
            continue
        try:
            gid = int(gid_raw)
        except ValueError:
            continue
        if gid < 1000 and name.casefold() not in ADMIN_GROUP_NAMES:
            continue
        members = sorted(
            {value.strip() for value in members_raw.split(",") if value.strip()},
            key=str.casefold,
        )
        items.append(
            {
                "name": name,
                "gid": gid,
                "source": "local",
                "members": members,
                "administrator_group": name.casefold() in ADMIN_GROUP_NAMES,
            }
        )
    return sorted(items, key=lambda item: str(item["name"]).casefold())


def snapshot() -> dict:
    domain_users = _domain_users()
    domain_groups = _domain_groups()
    domain_user_keys = {value.casefold() for value in domain_users}
    domain_group_keys = {value.casefold() for value in domain_groups}

    users = _local_users(domain_user_keys)
    for name in domain_users:
        identity = resolve_identity(name, "domain")
        users.append(
            {
                "username": name,
                "uid": identity.uid if identity else None,
                "gid": identity.gid if identity else None,
                "display_name": None,
                "home": None,
                "shell": None,
                "source": "domain",
                "is_admin": bool(identity and identity.is_admin),
            }
        )

    groups = _local_groups(domain_group_keys)
    groups.extend(
        {
            "name": name,
            "gid": None,
            "source": "domain",
            "members": [],
            "administrator_group": False,
        }
        for name in domain_groups
    )

    return {
        "users": sorted(users, key=lambda item: (str(item["source"]), str(item["username"]).casefold())),
        "groups": sorted(groups, key=lambda item: (str(item["source"]), str(item["name"]).casefold())),
        "authentication": {
            "pam": shutil.which("pamtester") is not None and Path("/etc/pam.d/srv-control").is_file(),
            "domain": bool(domain_users or domain_groups),
            "sso": Path("/var/lib/srv-control/http.keytab").is_file(),
        },
    }
