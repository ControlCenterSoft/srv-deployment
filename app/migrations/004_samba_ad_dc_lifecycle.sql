BEGIN;

ALTER TABLE control_center.ad_dc_profiles
    ADD COLUMN IF NOT EXISTS interface_name text,
    ADD COLUMN IF NOT EXISTS ipv4 inet,
    ADD COLUMN IF NOT EXISTS dns_forwarder inet,
    ADD COLUMN IF NOT EXISTS managed boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS provisioned_at timestamptz,
    ADD COLUMN IF NOT EXISTS health_state text NOT NULL DEFAULT 'unknown',
    ADD COLUMN IF NOT EXISTS last_health_at timestamptz;

CREATE TABLE IF NOT EXISTS control_center.ad_dc_lifecycle_jobs (
    job_id text PRIMARY KEY,
    action text NOT NULL,
    state text NOT NULL DEFAULT 'queued',
    profile_id text REFERENCES control_center.ad_dc_profiles(profile_id) ON DELETE SET NULL,
    request jsonb NOT NULL DEFAULT '{}'::jsonb,
    result jsonb NOT NULL DEFAULT '{}'::jsonb,
    backup_path text,
    error text,
    created_at timestamptz NOT NULL DEFAULT now(),
    started_at timestamptz,
    finished_at timestamptz,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ad_dc_lifecycle_jobs_created_idx
    ON control_center.ad_dc_lifecycle_jobs(created_at DESC);
CREATE INDEX IF NOT EXISTS ad_dc_lifecycle_jobs_state_idx
    ON control_center.ad_dc_lifecycle_jobs(state);

CREATE TABLE IF NOT EXISTS control_center.ad_dc_health_runs (
    id bigserial PRIMARY KEY,
    profile_id text REFERENCES control_center.ad_dc_profiles(profile_id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    healthy boolean NOT NULL DEFAULT false,
    checks jsonb NOT NULL DEFAULT '{}'::jsonb,
    details jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS ad_dc_health_created_idx
    ON control_center.ad_dc_health_runs(created_at DESC);

COMMIT;
