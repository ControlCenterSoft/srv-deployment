BEGIN;

CREATE TABLE IF NOT EXISTS control_center.ad_dc_readiness_runs (
    id bigserial PRIMARY KEY,
    created_at timestamptz NOT NULL DEFAULT now(),
    hostname text NOT NULL,
    fqdn text,
    ready boolean NOT NULL DEFAULT false,
    blockers jsonb NOT NULL DEFAULT '[]'::jsonb,
    warnings jsonb NOT NULL DEFAULT '[]'::jsonb,
    checks jsonb NOT NULL DEFAULT '{}'::jsonb,
    details jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS ad_dc_readiness_created_idx
    ON control_center.ad_dc_readiness_runs(created_at DESC);

CREATE TABLE IF NOT EXISTS control_center.ad_dc_change_plans (
    plan_id text PRIMARY KEY,
    state text NOT NULL DEFAULT 'draft',
    plan jsonb NOT NULL DEFAULT '{}'::jsonb,
    rollback jsonb NOT NULL DEFAULT '{}'::jsonb,
    checksum text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE control_center.ad_dc_profiles
    ADD COLUMN IF NOT EXISTS readiness_state text NOT NULL DEFAULT 'unknown',
    ADD COLUMN IF NOT EXISTS last_readiness_at timestamptz,
    ADD COLUMN IF NOT EXISTS planned_hostname text,
    ADD COLUMN IF NOT EXISTS planned_ipv4 inet;

COMMIT;
