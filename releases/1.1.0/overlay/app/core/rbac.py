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
SOURCES = {"local", "domain", "any"}


@dataclass(frozen=True)
class Permission:
    module: str
    access: str


def _group_keys(identity: Identity) -> set[str]:
    return {group.casefold() for group in identity.groups}


def permissions_for(identity: Identity) -> dict[str, str]:
    if identity.is_admin:
        return {module: "write" for module in MODULES}

    group_keys = _group_keys(identity)
    if not group_keys:
        return {}

    with engine.connect() as connection:
        rows = connection.execute(
            text(
                """
                SELECT group_name, source, module, access
                FROM rbac_group_permissions
                WHERE enabled = true
                  AND source IN ('any', :source)
                """
            ),
            {"source": "domain" if identity.auth_source in {"domain", "sso"} else "local"},
        ).mappings()

        result: dict[str, str] = {}
        for row in rows:
            if str(row["group_name"]).casefold() not in group_keys:
                continue
            module = str(row["module"])
            access = str(row["access"])
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
    current = permissions_for(identity).get(module)
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
            dict(row)
            for row in connection.execute(
                text(
                    """
                    SELECT id, group_name, source, module, access, enabled,
                           updated_by, updated_at
                    FROM rbac_group_permissions
                    ORDER BY source, group_name, module
                    """
                )
            ).mappings()
        ]


def upsert_grant(*, group_name: str, source: str, module: str, access: str, actor: str) -> dict:
    group_name = group_name.strip()
    source = source.strip().lower()
    module = module.strip().lower()
    access = access.strip().lower()
    if not group_name:
        raise ValueError("group_name is required")
    if source not in SOURCES:
        raise ValueError("invalid source")
    if module not in MODULES:
        raise ValueError("invalid module")
    if access not in ACCESS_LEVELS:
        raise ValueError("invalid access")

    with engine.begin() as connection:
        row = connection.execute(
            text(
                """
                INSERT INTO rbac_group_permissions
                    (group_name, source, module, access, enabled, updated_by)
                VALUES
                    (:group_name, :source, :module, :access, true, :actor)
                ON CONFLICT (group_name, source, module)
                DO UPDATE SET
                    access = EXCLUDED.access,
                    enabled = true,
                    updated_by = EXCLUDED.updated_by,
                    updated_at = now()
                RETURNING id, group_name, source, module, access, enabled,
                          updated_by, updated_at
                """
            ),
            {
                "group_name": group_name,
                "source": source,
                "module": module,
                "access": access,
                "actor": actor,
            },
        ).mappings().one()
        return dict(row)


def delete_grant(grant_id: int) -> bool:
    with engine.begin() as connection:
        result = connection.execute(
            text("DELETE FROM rbac_group_permissions WHERE id = :id"),
            {"id": grant_id},
        )
        return bool(result.rowcount)
