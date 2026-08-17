from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Column,
    Date,
    DateTime,
    ForeignKey,
    Integer,
    SmallInteger,
    String,
    Text,
    Time,
    UniqueConstraint,
    func,
    text,
)

from sqlalchemy.dialects.postgresql import JSONB

from .database import Base


JSON_EMPTY = text("'{}'::jsonb")


class Setting(Base):
    __tablename__ = "settings"

    key = Column(
        String(160),
        primary_key=True,
    )

    value = Column(
        JSONB,
        nullable=False,
        server_default=JSON_EMPTY,
    )

    description = Column(
        Text,
        nullable=True,
    )

    updated_at = Column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )


class ModuleSetting(Base):
    __tablename__ = "module_settings"

    id = Column(
        BigInteger,
        primary_key=True,
        autoincrement=True,
    )

    module = Column(
        String(80),
        nullable=False,
    )

    key = Column(
        String(160),
        nullable=False,
    )

    value = Column(
        JSONB,
        nullable=False,
        server_default=JSON_EMPTY,
    )

    updated_at = Column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    __table_args__ = (
        UniqueConstraint(
            "module",
            "key",
            name="uq_module_settings_module_key",
        ),
    )


class AuditEvent(Base):
    __tablename__ = "audit_events"

    id = Column(
        BigInteger,
        primary_key=True,
        autoincrement=True,
    )

    created_at = Column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        index=True,
    )

    actor = Column(
        String(160),
        nullable=True,
        index=True,
    )

    client_ip = Column(
        String(64),
        nullable=True,
    )

    module = Column(
        String(80),
        nullable=False,
        index=True,
    )

    action = Column(
        String(160),
        nullable=False,
        index=True,
    )

    object_type = Column(
        String(120),
        nullable=True,
    )

    object_id = Column(
        String(200),
        nullable=True,
    )

    success = Column(
        Boolean,
        nullable=False,
        server_default=text("true"),
    )

    details = Column(
        JSONB,
        nullable=False,
        server_default=JSON_EMPTY,
    )


class Job(Base):
    __tablename__ = "jobs"

    id = Column(
        BigInteger,
        primary_key=True,
        autoincrement=True,
    )

    module = Column(
        String(80),
        nullable=False,
        index=True,
    )

    kind = Column(
        String(160),
        nullable=False,
        index=True,
    )

    state = Column(
        String(32),
        nullable=False,
        server_default=text("'queued'"),
        index=True,
    )

    progress = Column(
        Integer,
        nullable=False,
        server_default=text("0"),
    )

    payload = Column(
        JSONB,
        nullable=False,
        server_default=JSON_EMPTY,
    )

    result = Column(
        JSONB,
        nullable=False,
        server_default=JSON_EMPTY,
    )

    error = Column(
        Text,
        nullable=True,
    )

    created_at = Column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    started_at = Column(
        DateTime(timezone=True),
        nullable=True,
    )

    finished_at = Column(
        DateTime(timezone=True),
        nullable=True,
    )

    __table_args__ = (
        CheckConstraint(
            "state IN ('queued','running','success','failed','cancelled')",
            name="ck_jobs_state",
        ),
        CheckConstraint(
            "progress >= 0 AND progress <= 100",
            name="ck_jobs_progress",
        ),
    )


class ServiceCache(Base):
    __tablename__ = "service_cache"

    service_name = Column(
        String(160),
        primary_key=True,
    )

    state = Column(
        String(40),
        nullable=False,
    )

    details = Column(
        JSONB,
        nullable=False,
        server_default=JSON_EMPTY,
    )

    sampled_at = Column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )


class Device(Base):
    __tablename__ = "devices"

    id = Column(
        BigInteger,
        primary_key=True,
        autoincrement=True,
    )

    mac = Column(
        String(17),
        nullable=False,
        unique=True,
        index=True,
    )

    hostname = Column(
        String(255),
        nullable=True,
        index=True,
    )

    computer_name = Column(
        String(63),
        nullable=True,
        index=True,
    )

    assigned_ad_user = Column(
        String(255),
        nullable=True,
        index=True,
    )

    description = Column(
        Text,
        nullable=True,
    )

    enabled = Column(
        Boolean,
        nullable=False,
        server_default=text("true"),
    )

    pxe_enabled = Column(
        Boolean,
        nullable=False,
        server_default=text("false"),
    )

    extra = Column(
        "metadata",
        JSONB,
        nullable=False,
        server_default=JSON_EMPTY,
    )

    created_at = Column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    updated_at = Column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )


class DeviceGroup(Base):
    __tablename__ = "device_groups"

    id = Column(
        BigInteger,
        primary_key=True,
        autoincrement=True,
    )

    name = Column(
        String(160),
        nullable=False,
        unique=True,
    )

    description = Column(
        Text,
        nullable=True,
    )

    created_at = Column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )


class DeviceGroupMember(Base):
    __tablename__ = "device_group_members"

    device_group_id = Column(
        BigInteger,
        ForeignKey(
            "device_groups.id",
            ondelete="CASCADE",
        ),
        primary_key=True,
    )

    device_id = Column(
        BigInteger,
        ForeignKey(
            "devices.id",
            ondelete="CASCADE",
        ),
        primary_key=True,
    )


class OSImage(Base):
    __tablename__ = "os_images"

    id = Column(
        BigInteger,
        primary_key=True,
        autoincrement=True,
    )

    kind = Column(
        String(20),
        nullable=False,
        index=True,
    )

    name = Column(
        String(255),
        nullable=False,
    )

    version = Column(
        String(120),
        nullable=True,
    )

    architecture = Column(
        String(40),
        nullable=False,
        server_default=text("'amd64'"),
    )

    source_path = Column(
        Text,
        nullable=False,
    )

    sha256 = Column(
        String(64),
        nullable=True,
    )

    enabled = Column(
        Boolean,
        nullable=False,
        server_default=text("true"),
    )

    extra = Column(
        "metadata",
        JSONB,
        nullable=False,
        server_default=JSON_EMPTY,
    )

    created_at = Column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    __table_args__ = (
        CheckConstraint(
            "kind IN ('windows','linux')",
            name="ck_os_images_kind",
        ),
    )


class PXEProfile(Base):
    __tablename__ = "pxe_profiles"

    id = Column(
        BigInteger,
        primary_key=True,
        autoincrement=True,
    )

    device_id = Column(
        BigInteger,
        ForeignKey(
            "devices.id",
            ondelete="CASCADE",
        ),
        nullable=False,
        unique=True,
    )

    os_image_id = Column(
        BigInteger,
        ForeignKey(
            "os_images.id",
            ondelete="SET NULL",
        ),
        nullable=True,
    )

    computer_name = Column(
        String(63),
        nullable=True,
    )

    windows_edition = Column(
        String(160),
        nullable=True,
    )

    locale = Column(
        String(32),
        nullable=False,
        server_default=text("'ru-RU'"),
    )

    timezone = Column(
        String(80),
        nullable=False,
        server_default=text("'Europe/Moscow'"),
    )

    auto_install = Column(
        Boolean,
        nullable=False,
        server_default=text("false"),
    )

    domain_join = Column(
        Boolean,
        nullable=False,
        server_default=text("true"),
    )

    config = Column(
        JSONB,
        nullable=False,
        server_default=JSON_EMPTY,
    )

    created_at = Column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    updated_at = Column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )


class SoftwareItem(Base):
    __tablename__ = "software_items"

    id = Column(
        BigInteger,
        primary_key=True,
        autoincrement=True,
    )

    name = Column(
        String(255),
        nullable=False,
    )

    version = Column(
        String(120),
        nullable=True,
    )

    platform = Column(
        String(40),
        nullable=False,
        server_default=text("'windows'"),
    )

    package_path = Column(
        Text,
        nullable=False,
    )

    sha256 = Column(
        String(64),
        nullable=True,
    )

    install_args = Column(
        Text,
        nullable=True,
    )

    enabled = Column(
        Boolean,
        nullable=False,
        server_default=text("true"),
    )

    extra = Column(
        "metadata",
        JSONB,
        nullable=False,
        server_default=JSON_EMPTY,
    )

    created_at = Column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )


class SoftwareGroup(Base):
    __tablename__ = "software_groups"

    id = Column(
        BigInteger,
        primary_key=True,
        autoincrement=True,
    )

    name = Column(
        String(160),
        nullable=False,
        unique=True,
    )

    description = Column(
        Text,
        nullable=True,
    )


class SoftwareGroupMember(Base):
    __tablename__ = "software_group_members"

    software_group_id = Column(
        BigInteger,
        ForeignKey(
            "software_groups.id",
            ondelete="CASCADE",
        ),
        primary_key=True,
    )

    software_item_id = Column(
        BigInteger,
        ForeignKey(
            "software_items.id",
            ondelete="CASCADE",
        ),
        primary_key=True,
    )


class PXEProfileSoftwareGroup(Base):
    __tablename__ = "pxe_profile_software_groups"

    pxe_profile_id = Column(
        BigInteger,
        ForeignKey(
            "pxe_profiles.id",
            ondelete="CASCADE",
        ),
        primary_key=True,
    )

    software_group_id = Column(
        BigInteger,
        ForeignKey(
            "software_groups.id",
            ondelete="CASCADE",
        ),
        primary_key=True,
    )


class VPNProfile(Base):
    __tablename__ = "vpn_profiles"

    id = Column(
        BigInteger,
        primary_key=True,
        autoincrement=True,
    )

    name = Column(
        String(160),
        nullable=False,
        unique=True,
    )

    provider = Column(
        String(80),
        nullable=False,
        server_default=text("'adguard'"),
    )

    enabled = Column(
        Boolean,
        nullable=False,
        server_default=text("false"),
    )

    credential_ref = Column(
        Text,
        nullable=True,
    )

    config = Column(
        JSONB,
        nullable=False,
        server_default=JSON_EMPTY,
    )

    created_at = Column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )


class DestinationList(Base):
    __tablename__ = "destination_lists"

    id = Column(
        BigInteger,
        primary_key=True,
        autoincrement=True,
    )

    name = Column(
        String(160),
        nullable=False,
        unique=True,
    )

    kind = Column(
        String(32),
        nullable=False,
        server_default=text("'custom'"),
    )

    source_type = Column(
        String(32),
        nullable=False,
        server_default=text("'manual'"),
    )

    source_url = Column(
        Text,
        nullable=True,
    )

    update_mode = Column(
        String(32),
        nullable=False,
        server_default=text("'manual'"),
    )

    update_time = Column(
        Time,
        nullable=True,
    )

    enabled = Column(
        Boolean,
        nullable=False,
        server_default=text("true"),
    )

    last_sync_at = Column(
        DateTime(timezone=True),
        nullable=True,
    )

    last_sync_status = Column(
        String(40),
        nullable=True,
    )

    config = Column(
        JSONB,
        nullable=False,
        server_default=JSON_EMPTY,
    )

    __table_args__ = (
        CheckConstraint(
            "kind IN ('rkn','custom','system')",
            name="ck_destination_lists_kind",
        ),
        CheckConstraint(
            "source_type IN ('manual','url','file')",
            name="ck_destination_lists_source_type",
        ),
        CheckConstraint(
            "update_mode IN ('manual','daily')",
            name="ck_destination_lists_update_mode",
        ),
    )


class DestinationEntry(Base):
    __tablename__ = "destination_entries"

    id = Column(
        BigInteger,
        primary_key=True,
        autoincrement=True,
    )

    destination_list_id = Column(
        BigInteger,
        ForeignKey(
            "destination_lists.id",
            ondelete="CASCADE",
        ),
        nullable=False,
        index=True,
    )

    entry_type = Column(
        String(20),
        nullable=False,
        index=True,
    )

    value = Column(
        Text,
        nullable=False,
    )

    normalized_value = Column(
        Text,
        nullable=False,
    )

    active = Column(
        Boolean,
        nullable=False,
        server_default=text("true"),
    )

    created_at = Column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    __table_args__ = (
        UniqueConstraint(
            "destination_list_id",
            "entry_type",
            "normalized_value",
            name="uq_destination_entry",
        ),
        CheckConstraint(
            "entry_type IN ('domain','ipv4','ipv6','cidr')",
            name="ck_destination_entries_type",
        ),
    )


class InternetPolicy(Base):
    __tablename__ = "internet_policies"

    id = Column(
        BigInteger,
        primary_key=True,
        autoincrement=True,
    )

    name = Column(
        String(160),
        nullable=False,
        unique=True,
    )

    description = Column(
        Text,
        nullable=True,
    )

    enabled = Column(
        Boolean,
        nullable=False,
        server_default=text("true"),
    )

    priority = Column(
        Integer,
        nullable=False,
        server_default=text("100"),
    )

    default_action = Column(
        String(20),
        nullable=False,
        server_default=text("'direct'"),
    )

    default_vpn_profile_id = Column(
        BigInteger,
        ForeignKey(
            "vpn_profiles.id",
            ondelete="SET NULL",
        ),
        nullable=True,
    )

    timezone = Column(
        String(80),
        nullable=False,
        server_default=text("'Europe/Moscow'"),
    )

    config = Column(
        JSONB,
        nullable=False,
        server_default=JSON_EMPTY,
    )

    __table_args__ = (
        CheckConstraint(
            "default_action IN ('direct','vpn','block')",
            name="ck_internet_policies_default_action",
        ),
    )


class InternetPolicyDevice(Base):
    __tablename__ = "internet_policy_devices"

    internet_policy_id = Column(
        BigInteger,
        ForeignKey(
            "internet_policies.id",
            ondelete="CASCADE",
        ),
        primary_key=True,
    )

    device_id = Column(
        BigInteger,
        ForeignKey(
            "devices.id",
            ondelete="CASCADE",
        ),
        primary_key=True,
    )


class InternetPolicyGroup(Base):
    __tablename__ = "internet_policy_groups"

    internet_policy_id = Column(
        BigInteger,
        ForeignKey(
            "internet_policies.id",
            ondelete="CASCADE",
        ),
        primary_key=True,
    )

    device_group_id = Column(
        BigInteger,
        ForeignKey(
            "device_groups.id",
            ondelete="CASCADE",
        ),
        primary_key=True,
    )


class Schedule(Base):
    __tablename__ = "schedules"

    id = Column(
        BigInteger,
        primary_key=True,
        autoincrement=True,
    )

    internet_policy_id = Column(
        BigInteger,
        ForeignKey(
            "internet_policies.id",
            ondelete="CASCADE",
        ),
        nullable=False,
        index=True,
    )

    name = Column(
        String(160),
        nullable=False,
    )

    enabled = Column(
        Boolean,
        nullable=False,
        server_default=text("true"),
    )

    __table_args__ = (
        UniqueConstraint(
            "internet_policy_id",
            "name",
            name="uq_schedule_policy_name",
        ),
    )


class SchedulePeriod(Base):
    __tablename__ = "schedule_periods"

    id = Column(
        BigInteger,
        primary_key=True,
        autoincrement=True,
    )

    schedule_id = Column(
        BigInteger,
        ForeignKey(
            "schedules.id",
            ondelete="CASCADE",
        ),
        nullable=False,
        index=True,
    )

    weekday = Column(
        SmallInteger,
        nullable=False,
    )

    start_time = Column(
        Time,
        nullable=False,
    )

    end_time = Column(
        Time,
        nullable=False,
    )

    __table_args__ = (
        CheckConstraint(
            "weekday >= 0 AND weekday <= 6",
            name="ck_schedule_periods_weekday",
        ),
    )


class TimeQuota(Base):
    __tablename__ = "time_quotas"

    id = Column(
        BigInteger,
        primary_key=True,
        autoincrement=True,
    )

    internet_policy_id = Column(
        BigInteger,
        ForeignKey(
            "internet_policies.id",
            ondelete="CASCADE",
        ),
        nullable=False,
        index=True,
    )

    weekday = Column(
        SmallInteger,
        nullable=True,
    )

    quota_minutes = Column(
        Integer,
        nullable=False,
    )

    enabled = Column(
        Boolean,
        nullable=False,
        server_default=text("true"),
    )

    __table_args__ = (
        CheckConstraint(
            "weekday IS NULL OR (weekday >= 0 AND weekday <= 6)",
            name="ck_time_quotas_weekday",
        ),
        CheckConstraint(
            "quota_minutes >= 0",
            name="ck_time_quotas_minutes",
        ),
    )


class QuotaUsage(Base):
    __tablename__ = "quota_usage"

    id = Column(
        BigInteger,
        primary_key=True,
        autoincrement=True,
    )

    device_id = Column(
        BigInteger,
        ForeignKey(
            "devices.id",
            ondelete="CASCADE",
        ),
        nullable=False,
        index=True,
    )

    usage_date = Column(
        Date,
        nullable=False,
        index=True,
    )

    used_seconds = Column(
        BigInteger,
        nullable=False,
        server_default=text("0"),
    )

    manual_bonus_seconds = Column(
        BigInteger,
        nullable=False,
        server_default=text("0"),
    )

    updated_at = Column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    __table_args__ = (
        UniqueConstraint(
            "device_id",
            "usage_date",
            name="uq_quota_usage_device_date",
        ),
        CheckConstraint(
            "used_seconds >= 0",
            name="ck_quota_usage_used",
        ),
    )


class RoutingRule(Base):
    __tablename__ = "routing_rules"

    id = Column(
        BigInteger,
        primary_key=True,
        autoincrement=True,
    )

    internet_policy_id = Column(
        BigInteger,
        ForeignKey(
            "internet_policies.id",
            ondelete="CASCADE",
        ),
        nullable=False,
        index=True,
    )

    destination_list_id = Column(
        BigInteger,
        ForeignKey(
            "destination_lists.id",
            ondelete="CASCADE",
        ),
        nullable=False,
        index=True,
    )

    action = Column(
        String(20),
        nullable=False,
    )

    vpn_profile_id = Column(
        BigInteger,
        ForeignKey(
            "vpn_profiles.id",
            ondelete="SET NULL",
        ),
        nullable=True,
    )

    priority = Column(
        Integer,
        nullable=False,
        server_default=text("100"),
    )

    enabled = Column(
        Boolean,
        nullable=False,
        server_default=text("true"),
    )

    __table_args__ = (
        CheckConstraint(
            "action IN ('direct','vpn','block')",
            name="ck_routing_rules_action",
        ),
    )


class ProxyProfile(Base):
    __tablename__ = "proxy_profiles"

    id = Column(
        BigInteger,
        primary_key=True,
        autoincrement=True,
    )

    name = Column(
        String(160),
        nullable=False,
        unique=True,
    )

    listen_host = Column(
        String(64),
        nullable=False,
        server_default=text("'127.0.0.1'"),
    )

    listen_port = Column(
        Integer,
        nullable=False,
    )

    route_action = Column(
        String(20),
        nullable=False,
        server_default=text("'direct'"),
    )

    vpn_profile_id = Column(
        BigInteger,
        ForeignKey(
            "vpn_profiles.id",
            ondelete="SET NULL",
        ),
        nullable=True,
    )

    enabled = Column(
        Boolean,
        nullable=False,
        server_default=text("false"),
    )

    config = Column(
        JSONB,
        nullable=False,
        server_default=JSON_EMPTY,
    )

    __table_args__ = (
        UniqueConstraint(
            "listen_host",
            "listen_port",
            name="uq_proxy_listen",
        ),
        CheckConstraint(
            "listen_port >= 1 AND listen_port <= 65535",
            name="ck_proxy_port",
        ),
        CheckConstraint(
            "route_action IN ('direct','vpn')",
            name="ck_proxy_route_action",
        ),
    )


class TrafficDaily(Base):
    __tablename__ = "traffic_daily"

    id = Column(
        BigInteger,
        primary_key=True,
        autoincrement=True,
    )

    device_id = Column(
        BigInteger,
        ForeignKey(
            "devices.id",
            ondelete="CASCADE",
        ),
        nullable=False,
        index=True,
    )

    traffic_date = Column(
        Date,
        nullable=False,
        index=True,
    )

    rx_bytes = Column(
        BigInteger,
        nullable=False,
        server_default=text("0"),
    )

    tx_bytes = Column(
        BigInteger,
        nullable=False,
        server_default=text("0"),
    )

    vpn_rx_bytes = Column(
        BigInteger,
        nullable=False,
        server_default=text("0"),
    )

    vpn_tx_bytes = Column(
        BigInteger,
        nullable=False,
        server_default=text("0"),
    )

    __table_args__ = (
        UniqueConstraint(
            "device_id",
            "traffic_date",
            name="uq_traffic_daily_device_date",
        ),
    )


class DockerStack(Base):
    __tablename__ = "docker_stacks"

    id = Column(
        BigInteger,
        primary_key=True,
        autoincrement=True,
    )

    name = Column(
        String(160),
        nullable=False,
        unique=True,
    )

    compose_path = Column(
        Text,
        nullable=False,
    )

    enabled = Column(
        Boolean,
        nullable=False,
        server_default=text("true"),
    )

    extra = Column(
        "metadata",
        JSONB,
        nullable=False,
        server_default=JSON_EMPTY,
    )

    created_at = Column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
