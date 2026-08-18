import hashlib
import json
import os
import socket
import time
from datetime import datetime, timezone
from pathlib import Path

import psycopg
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

DEFAULT_DSN = 'dbname=control_center user=control-center host=/var/run/postgresql'
DSN = os.getenv('CONTROL_CENTER_DB_DSN', DEFAULT_DSN)
SCHEMA = 'control_center'


class DatabaseUnavailable(RuntimeError):
    pass


def connect(*, autocommit=False):
    try:
        return psycopg.connect(DSN, connect_timeout=3, autocommit=autocommit, row_factory=dict_row)
    except Exception as exc:
        raise DatabaseUnavailable(str(exc)) from exc


def _epoch(value):
    if not value:
        return 0
    if isinstance(value, datetime):
        return int(value.timestamp())
    try:
        return int(value)
    except Exception:
        return 0


def health():
    with connect() as conn:
        row = conn.execute(
            "SELECT current_database() AS database, current_user AS role, "
            "current_setting('server_version') AS server_version, "
            "current_setting('server_version_num')::integer AS server_version_num"
        ).fetchone()
        migration = conn.execute(
            "SELECT version, name, applied_at FROM control_center.schema_migrations ORDER BY version DESC LIMIT 1"
        ).fetchone()
        node_count = conn.execute("SELECT count(*) AS count FROM control_center.cluster_nodes").fetchone()['count']
        row.update({
            'ok': True,
            'driver': 'psycopg3',
            'schema': SCHEMA,
            'migration': migration,
            'node_count': node_count,
            'cluster_ready': True,
        })
        if migration and migration.get('applied_at'):
            row['migration']['applied_at'] = migration['applied_at'].isoformat()
        return row


def get_setting(key, default=None):
    with connect() as conn:
        row = conn.execute("SELECT value FROM control_center.settings WHERE key=%s", (key,)).fetchone()
        return row['value'] if row else default


def set_setting(key, value):
    with connect() as conn:
        conn.execute(
            "INSERT INTO control_center.settings(key,value,updated_at) VALUES(%s,%s,now()) "
            "ON CONFLICT(key) DO UPDATE SET value=EXCLUDED.value, updated_at=now()",
            (key, Jsonb(value)),
        )
    return value


def set_setting_if_missing(key, value):
    with connect() as conn:
        row = conn.execute(
            "INSERT INTO control_center.settings(key,value) VALUES(%s,%s) "
            "ON CONFLICT(key) DO NOTHING RETURNING value",
            (key, Jsonb(value)),
        ).fetchone()
        if row:
            return row['value']
        row = conn.execute("SELECT value FROM control_center.settings WHERE key=%s", (key,)).fetchone()
        return row['value'] if row else value


def audit(action, resource, status, remote_addr=None, details=None):
    details = details or {}
    with connect() as conn:
        conn.execute(
            "INSERT INTO control_center.audit_events(action,resource,status,remote_addr,details) VALUES(%s,%s,%s,%s,%s)",
            (str(action)[:160], str(resource)[:240], str(status)[:80], str(remote_addr or '')[:128] or None, Jsonb(details)),
        )


def list_audit(limit=100):
    limit = max(1, min(int(limit), 500))
    with connect() as conn:
        rows = conn.execute(
            "SELECT id,created_at,action,resource,status,remote_addr,details "
            "FROM control_center.audit_events ORDER BY id DESC LIMIT %s",
            (limit,),
        ).fetchall()
    for row in rows:
        if row.get('created_at'):
            row['created_at'] = row['created_at'].isoformat()
    return rows


def sync_notifications(items):
    items = items or []
    with connect() as conn:
        for item in items:
            ts = _epoch(item.get('timestamp'))
            event_ts = datetime.fromtimestamp(ts, timezone.utc) if ts else None
            conn.execute(
                "INSERT INTO control_center.notification_events"
                "(event_id,source,title,state,severity,message,event_ts,last_seen_at) "
                "VALUES(%s,%s,%s,%s,%s,%s,%s,now()) "
                "ON CONFLICT(event_id) DO UPDATE SET "
                "source=EXCLUDED.source,title=EXCLUDED.title,state=EXCLUDED.state,severity=EXCLUDED.severity,"
                "message=EXCLUDED.message,event_ts=EXCLUDED.event_ts,last_seen_at=now()",
                (
                    str(item.get('id') or '')[:80],
                    str(item.get('source') or 'system')[:80],
                    str(item.get('title') or 'Control Center')[:160],
                    str(item.get('state') or 'info')[:80],
                    str(item.get('severity') or 'info') if str(item.get('severity') or 'info') in {'ok', 'error', 'info'} else 'info',
                    str(item.get('message') or '')[:4000],
                    event_ts,
                ),
            )


def list_notifications(limit=100):
    limit = max(1, min(int(limit), 300))
    with connect() as conn:
        rows = conn.execute(
            "SELECT event_id,source,title,state,severity,message,event_ts,last_seen_at,is_read "
            "FROM control_center.notification_events ORDER BY COALESCE(event_ts,last_seen_at) DESC LIMIT %s",
            (limit,),
        ).fetchall()
    result = []
    for row in rows:
        result.append({
            'id': row['event_id'],
            'source': row['source'],
            'title': row['title'],
            'state': row['state'],
            'severity': row['severity'],
            'message': row['message'],
            'timestamp': _epoch(row.get('event_ts') or row.get('last_seen_at')),
            'read': bool(row['is_read']),
        })
    return result


def mark_notifications(ids=None):
    with connect() as conn:
        if ids is None:
            cur = conn.execute("UPDATE control_center.notification_events SET is_read=true WHERE is_read=false")
            return cur.rowcount
        clean = [str(x)[:80] for x in ids if str(x).strip()]
        if not clean:
            return 0
        cur = conn.execute(
            "UPDATE control_center.notification_events SET is_read=true WHERE event_id = ANY(%s)",
            (clean,),
        )
        return cur.rowcount


def reset_notification(event_id):
    with connect() as conn:
        cur = conn.execute(
            "UPDATE control_center.notification_events SET is_read=false WHERE event_id=%s",
            (str(event_id)[:80],),
        )
        return cur.rowcount


def upsert_module(module_id, installed, state='unknown', version=None, metadata=None):
    with connect() as conn:
        conn.execute(
            "INSERT INTO control_center.module_inventory(module_id,installed,version,state,metadata,updated_at) "
            "VALUES(%s,%s,%s,%s,%s,now()) ON CONFLICT(module_id) DO UPDATE SET "
            "installed=EXCLUDED.installed,version=EXCLUDED.version,state=EXCLUDED.state,metadata=EXCLUDED.metadata,updated_at=now()",
            (module_id, bool(installed), version, state, Jsonb(metadata or {})),
        )


def sync_service_config(service_id, config, source='unknown'):
    with connect() as conn:
        conn.execute(
            "INSERT INTO control_center.service_configs(service_id,config,source,updated_at) VALUES(%s,%s,%s,now()) "
            "ON CONFLICT(service_id) DO UPDATE SET config=EXCLUDED.config,source=EXCLUDED.source,updated_at=now()",
            (service_id, Jsonb(config or {}), str(source)[:80]),
        )


def upsert_job(job_id, job_type, state, requested_by='web', message='', payload=None, result=None):
    with connect() as conn:
        conn.execute(
            "INSERT INTO control_center.jobs(job_id,job_type,state,requested_by,message,payload,result) "
            "VALUES(%s,%s,%s,%s,%s,%s,%s) ON CONFLICT(job_id) DO UPDATE SET "
            "state=EXCLUDED.state,message=EXCLUDED.message,result=EXCLUDED.result,"
            "started_at=CASE WHEN EXCLUDED.state='running' AND control_center.jobs.started_at IS NULL THEN now() ELSE control_center.jobs.started_at END,"
            "finished_at=CASE WHEN EXCLUDED.state IN ('ok','error','failed','done') THEN now() ELSE control_center.jobs.finished_at END",
            (job_id, job_type, state, requested_by, message, Jsonb(payload or {}), Jsonb(result or {})),
        )


def _device_node_id():
    try:
        machine_id = Path('/etc/machine-id').read_text().strip()
    except Exception:
        machine_id = socket.gethostname()
    return hashlib.sha256(machine_id.encode()).hexdigest()[:24]


def upsert_local_node(*, edition='Home', version='', build='', endpoint=None):
    node_id = _device_node_id()
    with connect() as conn:
        conn.execute(
            "INSERT INTO control_center.cluster_nodes"
            "(node_id,hostname,node_role,edition,endpoint,state,version,build,last_seen_at,updated_at) "
            "VALUES(%s,%s,'standalone',%s,%s,'online',%s,%s,now(),now()) "
            "ON CONFLICT(node_id) DO UPDATE SET hostname=EXCLUDED.hostname,edition=EXCLUDED.edition,"
            "endpoint=COALESCE(EXCLUDED.endpoint,control_center.cluster_nodes.endpoint),state='online',"
            "version=EXCLUDED.version,build=EXCLUDED.build,last_seen_at=now(),updated_at=now()",
            (node_id, socket.gethostname(), edition, endpoint, version, build),
        )
    return node_id


def cluster_nodes():
    with connect() as conn:
        rows = conn.execute(
            "SELECT node_id,hostname,node_role,edition,endpoint,state,version,build,last_seen_at,metadata "
            "FROM control_center.cluster_nodes ORDER BY hostname"
        ).fetchall()
    for row in rows:
        if row.get('last_seen_at'):
            row['last_seen_at'] = row['last_seen_at'].isoformat()
    return rows


def bootstrap_from_runtime(main_module):
    set_setting_if_missing('web.port', int(os.getenv('CONTROL_CENTER_PORT', '8080')))
    set_setting_if_missing('control_center.update', main_module._normalized_update_settings())
    set_setting_if_missing('os.update', main_module._normalized_os_update_settings())
    set_setting('release.current', {'version': main_module.APP_VERSION, 'build': main_module.APP_BUILD})
    lic = main_module._license_info()
    upsert_local_node(edition=lic.get('edition', 'Home'), version=main_module.APP_VERSION, build=main_module.APP_BUILD)
    try:
        network, _, source = main_module._effective_network_config()
        sync_service_config('network', network, source)
    except Exception:
        pass
    try:
        cfg, source = main_module._effective_dhcp_config()
        sync_service_config('dhcp', cfg, source)
        state = main_module._read_json(main_module.DHCP_STATE, {})
        upsert_module('dhcp', bool(state.get('installed')), 'installed' if state.get('installed') else 'available', metadata=state)
    except Exception:
        pass
    try:
        sync_notifications(main_module._notifications())
    except Exception:
        pass
