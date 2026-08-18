BEGIN;

CREATE TABLE IF NOT EXISTS control_center.ad_dc_profiles (
    profile_id text PRIMARY KEY,
    realm text,
    netbios_domain text,
    dns_backend text NOT NULL DEFAULT 'SAMBA_INTERNAL',
    functional_level text,
    site_name text NOT NULL DEFAULT 'Default-First-Site-Name',
    state text NOT NULL DEFAULT 'draft',
    config jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS control_center.ad_dc_nodes (
    node_id text PRIMARY KEY,
    profile_id text REFERENCES control_center.ad_dc_profiles(profile_id) ON DELETE SET NULL,
    dc_role text NOT NULL DEFAULT 'planned',
    hostname text NOT NULL,
    fqdn text,
    ipv4 inet,
    site_name text,
    state text NOT NULL DEFAULT 'planned',
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS control_center.ad_dc_preflight_runs (
    id bigserial PRIMARY KEY,
    created_at timestamptz NOT NULL DEFAULT now(),
    hostname text NOT NULL,
    fqdn text,
    ready boolean NOT NULL DEFAULT false,
    checks jsonb NOT NULL DEFAULT '{}'::jsonb,
    details jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS ad_dc_preflight_created_idx
    ON control_center.ad_dc_preflight_runs(created_at DESC);

COMMIT;
