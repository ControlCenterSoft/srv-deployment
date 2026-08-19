BEGIN;

CREATE TABLE IF NOT EXISTS control_center.rbac_roles (
    role_id text PRIMARY KEY,
    display_name text NOT NULL,
    system_role boolean NOT NULL DEFAULT false,
    permissions jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS control_center.rbac_bindings (
    id bigserial PRIMARY KEY,
    auth_source text NOT NULL CHECK (auth_source IN ('local','domain')),
    principal text NOT NULL,
    role_id text NOT NULL REFERENCES control_center.rbac_roles(role_id) ON DELETE RESTRICT,
    enabled boolean NOT NULL DEFAULT true,
    priority integer NOT NULL DEFAULT 100,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(auth_source, principal)
);
CREATE INDEX IF NOT EXISTS rbac_bindings_lookup_idx
    ON control_center.rbac_bindings(auth_source, principal, enabled, priority);

INSERT INTO control_center.rbac_roles(role_id,display_name,system_role,permissions)
VALUES
    ('admin','Администратор',true,'{"portal":"admin","write":true}'::jsonb),
    ('viewer','Наблюдатель',true,'{"portal":"viewer","write":false}'::jsonb)
ON CONFLICT (role_id) DO UPDATE SET
    display_name=EXCLUDED.display_name,
    system_role=true,
    permissions=EXCLUDED.permissions,
    updated_at=now();

CREATE TABLE IF NOT EXISTS control_center.service_dependencies (
    service_id text NOT NULL,
    depends_on text NOT NULL,
    required boolean NOT NULL DEFAULT true,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY(service_id, depends_on),
    CHECK(service_id <> depends_on)
);

INSERT INTO control_center.service_dependencies(service_id,depends_on,required,metadata)
VALUES
    ('domain','dns',true,'{"provider_when_domain":"samba_internal"}'::jsonb),
    ('domain','storage',true,'{"provider_when_domain":"samba_ad_dc"}'::jsonb)
ON CONFLICT (service_id,depends_on) DO UPDATE SET
    required=EXCLUDED.required,
    metadata=EXCLUDED.metadata;

CREATE TABLE IF NOT EXISTS control_center.dhcp_reservations (
    mac macaddr PRIMARY KEY,
    ipv4 inet NOT NULL,
    hostname text,
    enabled boolean NOT NULL DEFAULT true,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (family(ipv4) = 4)
);
CREATE UNIQUE INDEX IF NOT EXISTS dhcp_reservations_ipv4_enabled_idx
    ON control_center.dhcp_reservations(ipv4)
    WHERE enabled;

CREATE TABLE IF NOT EXISTS control_center.service_cleanup_audits (
    id bigserial PRIMARY KEY,
    service_id text NOT NULL,
    action text NOT NULL,
    clean boolean NOT NULL,
    checks jsonb NOT NULL DEFAULT '{}'::jsonb,
    recovery_path text,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS service_cleanup_audits_created_idx
    ON control_center.service_cleanup_audits(service_id, created_at DESC);

INSERT INTO control_center.settings(key,value)
VALUES
    ('auth.rbac_mode','"bootstrap"'::jsonb),
    ('auth.local_admin_group','"control-center-admins"'::jsonb),
    ('auth.domain_admin_group','"Control Center Admins"'::jsonb)
ON CONFLICT (key) DO NOTHING;

COMMIT;
