"""Server-side RBAC policy for Control Center.

UI visibility is never an authorization boundary. Every future privileged
operation must call this policy (or a stricter policy derived from it) on the
server side before executing any action.
"""

from __future__ import annotations

from enum import StrEnum


class Role(StrEnum):
    VIEWER = "viewer"
    ADMIN = "admin"


class Permission(StrEnum):
    ACCOUNT_READ = "account.read"
    ACCOUNT_SESSION_REVOKE = "account.session.revoke"
    SERVER_READ = "server.read"
    DIAGNOSTICS_READ = "diagnostics.read"
    ADMIN_USERS_READ = "admin.users.read"
    ADMIN_SERVERS_READ = "admin.servers.read"
    ADMIN_RELEASES_READ = "admin.releases.read"
    ADMIN_AUDIT_READ = "admin.audit.read"


ROLE_PERMISSIONS: dict[Role, frozenset[Permission]] = {
    Role.VIEWER: frozenset(
        {
            Permission.ACCOUNT_READ,
            Permission.SERVER_READ,
            Permission.DIAGNOSTICS_READ,
        }
    ),
    Role.ADMIN: frozenset(Permission),
}


def parse_role(value: str) -> Role:
    try:
        return Role(value)
    except ValueError as exc:
        raise ValueError("unknown role") from exc


def is_allowed(role: Role, permission: Permission) -> bool:
    return permission in ROLE_PERMISSIONS.get(role, frozenset())


def require_permission(role: Role, permission: Permission) -> None:
    if not is_allowed(role, permission):
        raise PermissionError(f"role {role.value} lacks permission {permission.value}")


def public_policy() -> dict[str, list[str]]:
    """Stable machine-readable policy contract for tests/SDK parity."""
    return {
        role.value: sorted(permission.value for permission in permissions)
        for role, permissions in ROLE_PERMISSIONS.items()
    }
