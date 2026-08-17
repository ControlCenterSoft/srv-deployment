"""allow shares module in RBAC

Revision ID: 13f0a1300001
Revises: 12f0a1200001
Create Date: 2026-08-17 19:15:00+03:00
"""

from typing import Sequence, Union

from alembic import op


revision: str = "13f0a1300001"
down_revision: Union[str, Sequence[str], None] = "12f0a1200001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_constraint("ck_rbac_group_module", "rbac_group_permissions", type_="check")
    op.create_check_constraint(
        "ck_rbac_group_module",
        "rbac_group_permissions",
        "module IN ('samba','shares','pxe','minecraft','docker','network','downloads','*')",
    )


def downgrade() -> None:
    op.execute("DELETE FROM rbac_group_permissions WHERE module = 'shares'")
    op.drop_constraint("ck_rbac_group_module", "rbac_group_permissions", type_="check")
    op.create_check_constraint(
        "ck_rbac_group_module",
        "rbac_group_permissions",
        "module IN ('samba','pxe','minecraft','docker','network','downloads','*')",
    )
