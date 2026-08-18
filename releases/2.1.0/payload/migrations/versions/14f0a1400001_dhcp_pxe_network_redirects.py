"""SRV Control Center 1.4 DHCP/PXE/network/folder redirects

Revision ID: 14f0a1400001
Revises: 13f0a1300001
Create Date: 2026-08-17 22:00:00+03:00
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = '14f0a1400001'
down_revision: Union[str, Sequence[str], None] = '13f0a1300001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'dhcp_configs',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('interface', sa.String(length=64), nullable=True),
        sa.Column('network', sa.String(length=64), nullable=True),
        sa.Column('netmask', sa.String(length=64), nullable=True),
        sa.Column('range_start', sa.String(length=64), nullable=True),
        sa.Column('range_end', sa.String(length=64), nullable=True),
        sa.Column('gateway', sa.String(length=64), nullable=True),
        sa.Column('dns', postgresql.JSONB(astext_type=sa.Text()), nullable=False, server_default=sa.text("'[]'::jsonb")),
        sa.Column('lease_time', sa.String(length=32), nullable=False, server_default='12h'),
        sa.Column('enabled', sa.Boolean(), nullable=False, server_default=sa.text('false')),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.CheckConstraint('id = 1', name='ck_dhcp_configs_singleton'),
    )
    op.create_table(
        'dhcp_options',
        sa.Column('id', sa.BigInteger(), primary_key=True, autoincrement=True),
        sa.Column('code', sa.Integer(), nullable=False),
        sa.Column('value', sa.Text(), nullable=False),
        sa.Column('enabled', sa.Boolean(), nullable=False, server_default=sa.text('true')),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.CheckConstraint('code >= 1 AND code <= 254', name='ck_dhcp_options_code'),
    )
    op.create_index('ix_dhcp_options_code', 'dhcp_options', ['code'])
    op.create_table(
        'dhcp_reservations',
        sa.Column('id', sa.BigInteger(), primary_key=True, autoincrement=True),
        sa.Column('mac', sa.String(length=17), nullable=False),
        sa.Column('ip_address', sa.String(length=64), nullable=False),
        sa.Column('hostname', sa.String(length=255), nullable=True),
        sa.Column('enabled', sa.Boolean(), nullable=False, server_default=sa.text('true')),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint('mac', name='uq_dhcp_reservation_mac'),
        sa.UniqueConstraint('ip_address', name='uq_dhcp_reservation_ip'),
    )

    op.add_column('pxe_profiles', sa.Column('status', sa.String(length=32), nullable=False, server_default='draft'))
    op.add_column('pxe_profiles', sa.Column('install_authorized', sa.Boolean(), nullable=False, server_default=sa.text('false')))
    op.add_column('pxe_profiles', sa.Column('one_time', sa.Boolean(), nullable=False, server_default=sa.text('true')))
    op.add_column('pxe_profiles', sa.Column('authorized_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('pxe_profiles', sa.Column('consumed_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('pxe_profiles', sa.Column('last_boot_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('pxe_profiles', sa.Column('last_result', sa.String(length=64), nullable=True))
    op.add_column('pxe_profiles', sa.Column('domain_name', sa.String(length=255), nullable=True))
    op.add_column('pxe_profiles', sa.Column('ip_address', sa.String(length=64), nullable=True))
    op.create_check_constraint(
        'ck_pxe_profiles_status', 'pxe_profiles',
        "status IN ('draft','publishing','authorized','installing','installed','failed','disabled')",
    )

    op.create_table(
        'pxe_configuration_profiles',
        sa.Column('id', sa.BigInteger(), primary_key=True, autoincrement=True),
        sa.Column('name', sa.String(length=160), nullable=False, unique=True),
        sa.Column('kind', sa.String(length=20), nullable=False, server_default='both'),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('config', postgresql.JSONB(astext_type=sa.Text()), nullable=False, server_default=sa.text("'{}'::jsonb")),
        sa.Column('enabled', sa.Boolean(), nullable=False, server_default=sa.text('true')),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.CheckConstraint("kind IN ('windows','linux','both')", name='ck_pxe_configuration_profiles_kind'),
    )
    op.create_table(
        'pxe_profile_configuration_profiles',
        sa.Column('pxe_profile_id', sa.BigInteger(), sa.ForeignKey('pxe_profiles.id', ondelete='CASCADE'), primary_key=True),
        sa.Column('configuration_profile_id', sa.BigInteger(), sa.ForeignKey('pxe_configuration_profiles.id', ondelete='CASCADE'), primary_key=True),
    )

    op.create_table(
        'folder_redirect_profiles',
        sa.Column('id', sa.BigInteger(), primary_key=True, autoincrement=True),
        sa.Column('name', sa.String(length=160), nullable=False, unique=True),
        sa.Column('source_path', sa.Text(), nullable=False),
        sa.Column('target_path', sa.Text(), nullable=False),
        sa.Column('mode', sa.String(length=32), nullable=False, server_default='auto'),
        sa.Column('enabled', sa.Boolean(), nullable=False, server_default=sa.text('true')),
        sa.Column('metadata', postgresql.JSONB(astext_type=sa.Text()), nullable=False, server_default=sa.text("'{}'::jsonb")),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.CheckConstraint("mode IN ('auto','folder-redirection','smb','symlink','junction')", name='ck_folder_redirect_profiles_mode'),
    )
    op.create_table(
        'folder_redirect_assignments',
        sa.Column('id', sa.BigInteger(), primary_key=True, autoincrement=True),
        sa.Column('profile_id', sa.BigInteger(), sa.ForeignKey('folder_redirect_profiles.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('subject_type', sa.String(length=32), nullable=False),
        sa.Column('subject_name', sa.String(length=255), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint('profile_id', 'subject_type', 'subject_name', name='uq_folder_redirect_assignment'),
        sa.CheckConstraint("subject_type IN ('user','group','computer','pxe-profile')", name='ck_folder_redirect_assignment_type'),
    )


def downgrade() -> None:
    op.drop_table('folder_redirect_assignments')
    op.drop_table('folder_redirect_profiles')
    op.drop_table('pxe_profile_configuration_profiles')
    op.drop_table('pxe_configuration_profiles')
    op.drop_constraint('ck_pxe_profiles_status', 'pxe_profiles', type_='check')
    for name in ('ip_address','domain_name','last_result','last_boot_at','consumed_at','authorized_at','one_time','install_authorized','status'):
        op.drop_column('pxe_profiles', name)
    op.drop_table('dhcp_reservations')
    op.drop_index('ix_dhcp_options_code', table_name='dhcp_options')
    op.drop_table('dhcp_options')
    op.drop_table('dhcp_configs')
