"""system account authentication and module group RBAC

Revision ID: 11f0a1100001
Revises: 690c18a03d40
Create Date: 2026-08-17 15:10:00+03:00
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "11f0a1100001"
down_revision: Union[str, Sequence[str], None] = "690c18a03d40"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "rbac_group_permissions",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("group_name", sa.String(length=255), nullable=False),
        sa.Column("source", sa.String(length=16), nullable=False, server_default=sa.text("'any'")),
        sa.Column("module", sa.String(length=80), nullable=False),
        sa.Column("access", sa.String(length=16), nullable=False),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("updated_by", sa.String(length=255), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.CheckConstraint("source IN ('local','domain','any')", name="ck_rbac_group_source"),
        sa.CheckConstraint("module IN ('samba','pxe','minecraft','docker','network','downloads')", name="ck_rbac_group_module"),
        sa.CheckConstraint("access IN ('read','write')", name="ck_rbac_group_access"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("group_name", "source", "module", name="uq_rbac_group_module"),
    )
    op.create_index("ix_rbac_group_permissions_group_name", "rbac_group_permissions", ["group_name"], unique=False)
    op.create_index("ix_rbac_group_permissions_module", "rbac_group_permissions", ["module"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_rbac_group_permissions_module", table_name="rbac_group_permissions")
    op.drop_index("ix_rbac_group_permissions_group_name", table_name="rbac_group_permissions")
    op.drop_table("rbac_group_permissions")
