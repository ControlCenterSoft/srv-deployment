"""Control Center SQLite state/configuration store schema v1.

The ordinary configuration table intentionally rejects secret-like keys.
Secrets will use a separate storage contract. Session rows accept only token
hashes, never raw bearer/session values.
"""

from __future__ import annotations

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import sqlite3
from typing import Any
import uuid

from .audit import SENSITIVE_KEY_RE, sanitize_audit_value
from .rbac import Role, parse_role

SCHEMA_VERSION = 1
DEFAULT_DB_PATH = Path("/var/lib/control-center/state.db")
USERNAME_RE = re.compile(r"^[a-z][a-z0-9._-]{2,63}$")
SETTING_KEY_RE = re.compile(r"^[a-z][a-z0-9._-]{1,127}$")
TOKEN_HASH_RE = re.compile(r"^[0-9a-f]{64}$")
MAX_SETTING_JSON_BYTES = 32_768
MAX_AUDIT_JSON_BYTES = 32_768


class StoreError(RuntimeError):
    pass


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def normalize_username(username: str) -> str:
    if not isinstance(username, str):
        raise ValueError("username must be a string")
    normalized = username.strip().lower()
    if not USERNAME_RE.fullmatch(normalized):
        raise ValueError("username must match [a-z][a-z0-9._-]{2,63}")
    return normalized


def connect_store(path: str | Path | None = None) -> sqlite3.Connection:
    db_path = Path(path or os.environ.get("CONTROL_CENTER_STATE_DB") or DEFAULT_DB_PATH)
    db_path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(str(db_path), timeout=5.0)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    connection.execute("PRAGMA busy_timeout = 5000")
    return connection


def schema_version(connection: sqlite3.Connection) -> int:
    connection.execute(
        """
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version INTEGER PRIMARY KEY,
            applied_at TEXT NOT NULL
        )
        """
    )
    connection.commit()
    row = connection.execute("SELECT MAX(version) AS version FROM schema_migrations").fetchone()
    return int(row["version"] or 0)


def migrate_store(connection: sqlite3.Connection) -> int:
    current = schema_version(connection)
    if current > SCHEMA_VERSION:
        raise StoreError(
            f"state database schema {current} is newer than supported {SCHEMA_VERSION}"
        )
    if current == SCHEMA_VERSION:
        return current

    if current == 0:
        applied_at = utc_now().replace("'", "''")
        try:
            connection.executescript(
                f"""
                BEGIN IMMEDIATE;
                CREATE TABLE accounts (
                    id TEXT PRIMARY KEY,
                    username TEXT NOT NULL UNIQUE COLLATE NOCASE,
                    role TEXT NOT NULL CHECK(role IN ('viewer','admin')),
                    password_hash TEXT NOT NULL,
                    enabled INTEGER NOT NULL DEFAULT 1 CHECK(enabled IN (0,1)),
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE TABLE sessions (
                    id TEXT PRIMARY KEY,
                    account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
                    token_hash TEXT NOT NULL UNIQUE CHECK(length(token_hash) = 64),
                    created_at TEXT NOT NULL,
                    expires_at TEXT NOT NULL,
                    revoked_at TEXT
                );
                CREATE INDEX sessions_account_id_idx ON sessions(account_id);
                CREATE INDEX sessions_expires_at_idx ON sessions(expires_at);
                CREATE TABLE settings (
                    key TEXT PRIMARY KEY,
                    value_json TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE TABLE audit_events (
                    event_id TEXT PRIMARY KEY,
                    occurred_at TEXT NOT NULL,
                    correlation_id TEXT NOT NULL,
                    actor_id TEXT,
                    role TEXT,
                    action TEXT NOT NULL,
                    outcome TEXT NOT NULL,
                    target TEXT,
                    details_json TEXT NOT NULL
                );
                CREATE INDEX audit_occurred_at_idx ON audit_events(occurred_at);
                CREATE INDEX audit_correlation_id_idx ON audit_events(correlation_id);
                INSERT INTO schema_migrations(version, applied_at)
                VALUES (1, '{applied_at}');
                COMMIT;
                """
            )
        except sqlite3.Error as exc:
            try:
                connection.execute("ROLLBACK")
            except sqlite3.Error:
                pass
            raise StoreError(f"schema migration 1 failed: {exc}") from exc
        current = 1

    if current != SCHEMA_VERSION:
        raise StoreError(f"no forward migration path from schema {current}")
    return current


def initialize_store(path: str | Path | None = None) -> sqlite3.Connection:
    connection = connect_store(path)
    try:
        migrate_store(connection)
    except Exception:
        connection.close()
        raise
    return connection


def create_account(
    connection: sqlite3.Connection,
    *,
    username: str,
    role: Role | str,
    password_hash: str,
) -> str:
    normalized = normalize_username(username)
    parsed_role = role if isinstance(role, Role) else parse_role(role)
    if not isinstance(password_hash, str) or not password_hash.startswith("scrypt$"):
        raise ValueError("password_hash must use the approved scrypt format")
    if len(password_hash) > 512:
        raise ValueError("password_hash is too long")
    account_id = str(uuid.uuid4())
    now = utc_now()
    try:
        connection.execute(
            """
            INSERT INTO accounts(id, username, role, password_hash, enabled, created_at, updated_at)
            VALUES (?, ?, ?, ?, 1, ?, ?)
            """,
            (account_id, normalized, parsed_role.value, password_hash, now, now),
        )
        connection.commit()
    except sqlite3.IntegrityError as exc:
        raise StoreError("account could not be created") from exc
    return account_id


def find_account_by_username(
    connection: sqlite3.Connection, username: str
) -> dict[str, Any] | None:
    normalized = normalize_username(username)
    row = connection.execute(
        "SELECT id, username, role, password_hash, enabled, created_at, updated_at "
        "FROM accounts WHERE username = ? COLLATE NOCASE",
        (normalized,),
    ).fetchone()
    return dict(row) if row else None


def store_session(
    connection: sqlite3.Connection,
    *,
    account_id: str,
    token_hash: str,
    expires_at: str,
) -> str:
    if not TOKEN_HASH_RE.fullmatch(token_hash):
        raise ValueError("session storage accepts only SHA-256 token hashes")
    if not isinstance(expires_at, str) or not expires_at.endswith("Z") or len(expires_at) > 64:
        raise ValueError("expires_at must be a bounded UTC RFC3339 string")
    session_id = str(uuid.uuid4())
    try:
        connection.execute(
            """
            INSERT INTO sessions(id, account_id, token_hash, created_at, expires_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            (session_id, account_id, token_hash, utc_now(), expires_at),
        )
        connection.commit()
    except sqlite3.IntegrityError as exc:
        raise StoreError("session could not be stored") from exc
    return session_id


def put_setting(connection: sqlite3.Connection, key: str, value: Any) -> None:
    if not isinstance(key, str) or not SETTING_KEY_RE.fullmatch(key):
        raise ValueError("invalid setting key")
    if SENSITIVE_KEY_RE.search(key):
        raise ValueError("secret-like settings require the separate secrets store")
    encoded = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    if len(encoded.encode("utf-8")) > MAX_SETTING_JSON_BYTES:
        raise ValueError("setting value is too large")
    connection.execute(
        """
        INSERT INTO settings(key, value_json, updated_at) VALUES (?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET value_json=excluded.value_json, updated_at=excluded.updated_at
        """,
        (key, encoded, utc_now()),
    )
    connection.commit()


def get_setting(connection: sqlite3.Connection, key: str) -> Any | None:
    if not isinstance(key, str) or not SETTING_KEY_RE.fullmatch(key):
        raise ValueError("invalid setting key")
    row = connection.execute("SELECT value_json FROM settings WHERE key = ?", (key,)).fetchone()
    return json.loads(row["value_json"]) if row else None


def append_audit_event(connection: sqlite3.Connection, event: dict[str, Any]) -> None:
    required = {
        "event_id",
        "occurred_at",
        "correlation_id",
        "actor_id",
        "role",
        "action",
        "outcome",
        "target",
        "details",
    }
    if not isinstance(event, dict) or not required.issubset(event):
        raise ValueError("invalid audit event")
    details = json.dumps(
        sanitize_audit_value(event["details"]),
        ensure_ascii=False,
        separators=(",", ":"),
    )
    if len(details.encode("utf-8")) > MAX_AUDIT_JSON_BYTES:
        raise ValueError("audit details are too large")
    try:
        connection.execute(
            """
            INSERT INTO audit_events(
                event_id, occurred_at, correlation_id, actor_id, role,
                action, outcome, target, details_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                str(event["event_id"]),
                str(event["occurred_at"]),
                str(event["correlation_id"]),
                str(event["actor_id"]) if event["actor_id"] is not None else None,
                str(event["role"]) if event["role"] is not None else None,
                str(event["action"]),
                str(event["outcome"]),
                str(event["target"]) if event["target"] is not None else None,
                details,
            ),
        )
        connection.commit()
    except sqlite3.IntegrityError as exc:
        raise StoreError("audit event could not be stored") from exc
