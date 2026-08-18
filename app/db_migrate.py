#!/usr/bin/env python3
import hashlib
import os
from pathlib import Path

import psycopg

DSN = os.getenv('CONTROL_CENTER_DB_DSN', 'dbname=control_center user=control-center host=/var/run/postgresql')
MIGRATIONS = Path(__file__).resolve().parent / 'migrations'


def main():
    with psycopg.connect(DSN, connect_timeout=5) as conn:
        conn.execute('CREATE SCHEMA IF NOT EXISTS control_center')
        conn.execute(
            "CREATE TABLE IF NOT EXISTS control_center.schema_migrations("
            "version text PRIMARY KEY,name text NOT NULL,checksum text NOT NULL,applied_at timestamptz NOT NULL DEFAULT now())"
        )
        conn.commit()
        files = sorted(MIGRATIONS.glob('*.sql'))
        if not files:
            raise SystemExit('No PostgreSQL migrations found')
        for path in files:
            version = path.name.split('_', 1)[0]
            sql = path.read_text(encoding='utf-8')
            checksum = hashlib.sha256(sql.encode()).hexdigest()
            row = conn.execute(
                'SELECT checksum FROM control_center.schema_migrations WHERE version=%s',
                (version,),
            ).fetchone()
            if row:
                if row[0] != checksum:
                    raise SystemExit(f'Migration {version} checksum mismatch')
                print(f'SKIP {path.name}')
                continue
            try:
                with conn.transaction():
                    conn.execute(sql, prepare=False)
                    conn.execute(
                        'INSERT INTO control_center.schema_migrations(version,name,checksum) VALUES(%s,%s,%s)',
                        (version, path.name, checksum),
                    )
                print(f'APPLY {path.name}')
            except Exception:
                conn.rollback()
                raise
        row = conn.execute(
            'SELECT version,name FROM control_center.schema_migrations ORDER BY version DESC LIMIT 1'
        ).fetchone()
        print(f'POSTGRESQL SCHEMA OK: {row[0]} {row[1]}')


if __name__ == '__main__':
    main()
