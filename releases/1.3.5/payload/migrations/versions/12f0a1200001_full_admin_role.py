"""add full administrator RBAC role

Revision ID: 12f0a1200001
Revises: 11f0a1100002
Create Date: 2026-08-17 17:35:00+03:00
"""

from typing import Sequence, Union

from alembic import op


revision: str = "12f0a1200001"
down_revision: Union[str, Sequence[str], None] = "11f0a1100002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_constraint("ck_rbac_group_module", "rbac_group_permissions", type_="check")
    op.drop_constraint("ck_rbac_group_access", "rbac_group_permissions", type_="check")
    op.create_check_constraint(
        "ck_rbac_group_module",
        "rbac_group_permissions",
        "module IN ('samba','pxe','minecraft','docker','network','downloads','*')",
    )
    op.create_check_constraint(
        "ck_rbac_group_access",
        "rbac_group_permissions",
        "access IN ('read','write','admin')",
    )


def downgrade() -> None:
    op.execute("DELETE FROM rbac_group_permissions WHERE module = '*' OR access = 'admin'")
    op.drop_constraint("ck_rbac_group_access", "rbac_group_permissions", type_="check")
    op.drop_constraint("ck_rbac_group_module", "rbac_group_permissions", type_="check")
    op.create_check_constraint(
        "ck_rbac_group_module",
        "rbac_group_permissions",
        "module IN ('samba','pxe','minecraft','docker','network','downloads')",
    )
    op.create_check_constraint(
        "ck_rbac_group_access",
        "rbac_group_permissions",
        "access IN ('read','write')",
    )
