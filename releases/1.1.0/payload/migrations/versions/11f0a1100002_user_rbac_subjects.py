"""support direct user and group RBAC subjects

Revision ID: 11f0a1100002
Revises: 11f0a1100001
Create Date: 2026-08-17 17:05:00+03:00
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "11f0a1100002"
down_revision: Union[str, Sequence[str], None] = "11f0a1100001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "rbac_group_permissions",
        sa.Column(
            "subject_type",
            sa.String(length=16),
            nullable=False,
            server_default=sa.text("'group'"),
        ),
    )
    op.create_check_constraint(
        "ck_rbac_subject_type",
        "rbac_group_permissions",
        "subject_type IN ('group','user')",
    )
    op.drop_constraint(
        "uq_rbac_group_module",
        "rbac_group_permissions",
        type_="unique",
    )
    op.create_unique_constraint(
        "uq_rbac_subject_module",
        "rbac_group_permissions",
        ["subject_type", "group_name", "source", "module"],
    )
    op.create_index(
        "ix_rbac_subject_type",
        "rbac_group_permissions",
        ["subject_type"],
        unique=False,
    )


def downgrade() -> None:
    op.execute("DELETE FROM rbac_group_permissions WHERE subject_type = 'user'")
    op.drop_index("ix_rbac_subject_type", table_name="rbac_group_permissions")
    op.drop_constraint(
        "uq_rbac_subject_module",
        "rbac_group_permissions",
        type_="unique",
    )
    op.create_unique_constraint(
        "uq_rbac_group_module",
        "rbac_group_permissions",
        ["group_name", "source", "module"],
    )
    op.drop_constraint(
        "ck_rbac_subject_type",
        "rbac_group_permissions",
        type_="check",
    )
    op.drop_column("rbac_group_permissions", "subject_type")
