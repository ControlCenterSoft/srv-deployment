from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy import text

from app.core.system_auth import Identity
from app.database import engine


MODULES = {
    "samba": "Домен / Samba",
    "pxe": "PXE сервер",
    "minecraft": "Minecraft",
    "docker": "Docker",
    "network": "Сеть",
    "downloads": "Торренты",
}
ACCESS_LEVELS = {"read", "write"}
GRANT_ACCESS_LEVELS = {"read", "write", "admin"}
SOURCES = {"local", "domain", "any"}
SUBJECT_TYPES = {"group", "user"}
FULL_ADMIN_MODULE = "*"
FULL_ADMIN_PERMISSION_KEY = "__admin__"


@dataclass(frozen=True)
class Permission:
    module: str
    access: str


def _name_keys(value: str) -> set[str]:
    raw = str(value or "").strip().casefold()
    if not raw:
        return set()
    values = {raw}
    if "\\" in raw:
        local = raw.rsplit("\\", 1)[-1].strip()
        if local:
            values.add(local)
    if "@" in raw:
        local = raw.split("@", 1)[0].strip()
        if local:
            values.add(local)
    return values


def _group_keys(identity: Identity) -> set[str]:
    keys: set[str] = set()
    for group in identity.groups:
        keys.update(_name_keys(group))
    return keys


def _user_keys(identity: Identity) -> set[str]:
    return _name_keys(identity.username)


def _source_for_identity(identity: Identity) -> str:
    return "domain" if identity.auth_source in {"domain", "sso"} else "local"


def _matching_grants(identity: Identity) -> list[dict]:
    group_keys = _group_keys(identity)
    user_keys = _user_keys(identity)
    source = _source_for_identity(identity)
    matches: list[dict] = []

    with engine.connect() as connection:
        rows = connection.execute(
            text(
                """
                SELECT group_name, source, subject_type, module, access
                FROM rbac_group_permissions
                WHERE enabled = true
                  AND source IN ('any', :source)
                """
            ),
            {"source": source},
        ).mappings()
        for row in rows:
            subject_type = str(row.get("subject_type") or "group")
            subject_keys = _name_keys(str(row["group_name"]))
            if subject_type == "group":
                applies = bool(subject_keys & group_keys)
            elif subject_type == "user":
                applies = bool(subject_keys & user_keys)
            else:
                applies = False
            if applies:
                matches.append(dict(row))
    return matches


def is_full_admin(identity: Identity) -> bool:
    if identity.is_admin:
        return True
    return any(
        str(row.get("module")) == FULL_ADMIN_MODULE
        and str(row.get("access")) == "admin"
        for row in _matching_grants(identity)
    )


def permissions_for(identity: Identity) -> dict[str, str]:
    if identity.is_admin:
        return {
            **{module: "write" for module in MODULES},
            FULL_ADMIN_PERMISSION_KEY: "admin",
        }

    rows = _matching_grants(identity)
    if any(
        str(row.get("module")) == FULL_ADMIN_MODULE
        and str(row.get("access")) == "admin"
        for row in rows
    ):
        return {
            **{module: "write" for module in MODULES},
            FULL_ADMIN_PERMISSION_KEY: "admin",
        }

    result: dict[str, str] = {}
    for row in rows:
        module = str(row.get("module") or "")
        access = str(row.get("access") or "")
        if module not in MODULES or access not in ACCESS_LEVELS:
            continue
        if result.get(module) == "write":
            continue
        result[module] = access
    return result


def has_permission(identity: Identity, module: str, access: str = "read") -> bool:
    if module not in MODULES or access not in ACCESS_LEVELS:
        return False
    if identity.is_admin:
        return True
    permissions = permissions_for(identity)
    if permissions.get(FULL_ADMIN_PERMISSION_KEY) == "admin":
        return True
    current = permissions.get(module)
    if current == "write":
        return True
    return current == "read" and access == "read"


def require_permission(identity: Identity, module: str, access: str = "read") -> None:
    from fastapi import HTTPException

    if not has_permission(identity, module, access):
        raise HTTPException(status_code=403, detail="insufficient module permission")


def list_grants() -> list[dict]:
    with engine.connect() as connection:
        return [
            {**dict(row), "subject_name": row["group_name"]}
            for row in connection.execute(
                text(
                    """
                    SELECT id, group_name, subject_type, source, module, access, enabled,
                           updated_by, updated_at
                    FROM rbac_group_permissions
                    ORDER BY CASE WHEN access = 'admin' THEN 0 ELSE 1 END,
                             subject_type, source, group_name, module
                    """
                )
            ).mappings()
        ]


def upsert_grant(
    *,
    source: str,
    module: str,
    access: str,
    actor: str,
    subject_type: str = "group",
    subject_name: str = "",
    group_name: str | None = None,
) -> dict:
    subject_type = subject_type.strip().lower()
    subject_name = (subject_name or group_name or "").strip()
    source = source.strip().lower()
    module = module.strip().lower()
    access = access.strip().lower()

    if subject_type not in SUBJECT_TYPES:
        raise ValueError("invalid subject_type")
    if not subject_name:
        raise ValueError("subject_name is required")
    if source not in SOURCES:
        raise ValueError("invalid source")
    if access not in GRANT_ACCESS_LEVELS:
        raise ValueError("invalid access")
    if access == "admin":
        module = FULL_ADMIN_MODULE
    elif module not in MODULES:
        raise ValueError("invalid module")

    with engine.begin() as connection:
        row = connection.execute(
            text(
                """
                INSERT INTO rbac_group_permissions
                    (group_name, subject_type, source, module, access, enabled, updated_by)
                VALUES
                    (:subject_name, :subject_type, :source, :module, :access, true, :actor)
                ON CONFLICT (subject_type, group_name, source, module)
                DO UPDATE SET
                    access = EXCLUDED.access,
                    enabled = true,
                    updated_by = EXCLUDED.updated_by,
                    updated_at = now()
                RETURNING id, group_name, subject_type, source, module, access, enabled,
                          updated_by, updated_at
                """
            ),
            {
                "subject_name": subject_name,
                "subject_type": subject_type,
                "source": source,
                "module": module,
                "access": access,
                "actor": actor,
            },
        ).mappings().one()
        result = dict(row)
        result["subject_name"] = result["group_name"]
        return result


def delete_grant(grant_id: int) -> bool:
    with engine.begin() as connection:
        result = connection.execute(
            text("DELETE FROM rbac_group_permissions WHERE id = :id"),
            {"id": grant_id},
        )
        return bool(result.rowcount)
