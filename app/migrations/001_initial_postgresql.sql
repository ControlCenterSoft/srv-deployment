CREATE TABLE IF NOT EXISTS control_center.settings (
    key text PRIMARY KEY,
    value jsonb NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS control_center.notification_events (
    event_id text PRIMARY KEY,
    source text NOT NULL,
    title text NOT NULL,
    state text NOT NULL,
    severity text NOT NULL CHECK (severity IN ('ok','error','info')),
    message text NOT NULL,
    event_ts timestamptz,
    first_seen_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    is_read boolean NOT NULL DEFAULT false
);
CREATE INDEX IF NOT EXISTS notification_events_last_seen_idx ON control_center.notification_events(last_seen_at DESC);
CREATE INDEX IF NOT EXISTS notification_events_unread_idx ON control_center.notification_events(is_read, last_seen_at DESC);

CREATE TABLE IF NOT EXISTS control_center.audit_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    created_at timestamptz NOT NULL DEFAULT now(),
    action text NOT NULL,
    resource text NOT NULL,
    status text NOT NULL,
    remote_addr text,
    details jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS audit_events_created_idx ON control_center.audit_events(created_at DESC);

CREATE TABLE IF NOT EXISTS control_center.jobs (
    job_id text PRIMARY KEY,
    job_type text NOT NULL,
    state text NOT NULL,
    requested_at timestamptz NOT NULL DEFAULT now(),
    started_at timestamptz,
    finished_at timestamptz,
    requested_by text,
    message text,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    result jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS jobs_state_idx ON control_center.jobs(state, requested_at DESC);

CREATE TABLE IF NOT EXISTS control_center.module_inventory (
    module_id text PRIMARY KEY,
    installed boolean NOT NULL DEFAULT false,
    version text,
    state text NOT NULL DEFAULT 'unknown',
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS control_center.service_configs (
    service_id text PRIMARY KEY,
    config jsonb NOT NULL DEFAULT '{}'::jsonb,
    source text NOT NULL DEFAULT 'unknown',
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS control_center.cluster_nodes (
    node_id text PRIMARY KEY,
    hostname text NOT NULL,
    node_role text NOT NULL DEFAULT 'standalone' CHECK (node_role IN ('standalone','primary','secondary','witness')),
    edition text NOT NULL DEFAULT 'Home',
    endpoint text,
    state text NOT NULL DEFAULT 'online',
    version text,
    build text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS cluster_nodes_state_idx ON control_center.cluster_nodes(state, last_seen_at DESC);

INSERT INTO control_center.settings(key,value)
VALUES
    ('database.mode', '"local"'::jsonb),
    ('cluster.enabled', 'false'::jsonb)
ON CONFLICT (key) DO NOTHING;
