from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from api.audit import build_audit_event  # noqa: E402
from api.rbac import Role  # noqa: E402
from api.security import hash_password, hash_session_token, issue_session_token  # noqa: E402
from api.store import (  # noqa: E402
    SCHEMA_VERSION,
    StoreError,
    append_audit_event,
    create_account,
    find_account_by_username,
    get_setting,
    initialize_store,
    migrate_store,
    put_setting,
    schema_version,
    store_session,
)


class StoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmp.name) / "state.db"
        self.connection = initialize_store(self.db_path)

    def tearDown(self) -> None:
        self.connection.close()
        self.tmp.cleanup()

    def test_schema_v1_is_created_and_idempotent(self) -> None:
        self.assertEqual(schema_version(self.connection), SCHEMA_VERSION)
        self.assertEqual(migrate_store(self.connection), SCHEMA_VERSION)
        tables = {
            row["name"]
            for row in self.connection.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            ).fetchall()
        }
        self.assertTrue(
            {"schema_migrations", "accounts", "sessions", "settings", "audit_events"}
            <= tables
        )

    def test_newer_schema_fails_closed(self) -> None:
        self.connection.execute(
            "INSERT INTO schema_migrations(version, applied_at) VALUES (2, 'future')"
        )
        self.connection.commit()
        with self.assertRaises(StoreError):
            migrate_store(self.connection)

    def test_account_is_normalized_and_password_hash_only_is_stored(self) -> None:
        password = "Long Local Admin Password 2026!"
        password_hash = hash_password(password)
        account_id = create_account(
            self.connection,
            username="Local.Admin",
            role=Role.ADMIN,
            password_hash=password_hash,
        )
        account = find_account_by_username(self.connection, "LOCAL.ADMIN")
        self.assertEqual(account["id"], account_id)
        self.assertEqual(account["username"], "local.admin")
        self.assertEqual(account["role"], "admin")
        self.assertEqual(account["password_hash"], password_hash)
        self.assertNotIn(password, account["password_hash"])

    def test_duplicate_account_fails_without_leaking_database_detail(self) -> None:
        password_hash = hash_password("Another Long Password 2026!")
        create_account(
            self.connection,
            username="viewer",
            role=Role.VIEWER,
            password_hash=password_hash,
        )
        with self.assertRaisesRegex(StoreError, "account could not be created"):
            create_account(
                self.connection,
                username="VIEWER",
                role=Role.VIEWER,
                password_hash=password_hash,
            )

    def test_session_storage_accepts_digest_not_raw_token(self) -> None:
        account_id = create_account(
            self.connection,
            username="admin",
            role=Role.ADMIN,
            password_hash=hash_password("Admin Password For Store 2026!"),
        )
        raw_token = issue_session_token()
        token_hash = hash_session_token(raw_token)
        session_id = store_session(
            self.connection,
            account_id=account_id,
            token_hash=token_hash,
            expires_at="2030-01-01T00:00:00Z",
        )
        row = self.connection.execute(
            "SELECT id, token_hash FROM sessions WHERE id = ?", (session_id,)
        ).fetchone()
        self.assertEqual(row["token_hash"], token_hash)
        self.assertNotEqual(row["token_hash"], raw_token)
        with self.assertRaises(ValueError):
            store_session(
                self.connection,
                account_id=account_id,
                token_hash=raw_token,
                expires_at="2030-01-01T00:00:00Z",
            )

    def test_non_secret_setting_round_trip_and_secret_key_rejection(self) -> None:
        value = {"locale": "ru", "page_size": 25}
        put_setting(self.connection, "ui.preferences", value)
        self.assertEqual(get_setting(self.connection, "ui.preferences"), value)
        with self.assertRaisesRegex(ValueError, "secrets store"):
            put_setting(self.connection, "service.api_token", "must-not-live-here")

    def test_audit_persistence_redacts_secret_fields(self) -> None:
        event = build_audit_event(
            correlation_id="corr-1",
            actor_id="admin",
            role="admin",
            action="account.test",
            outcome="success",
            details={"password": "never-store", "safe": "visible"},
        )
        append_audit_event(self.connection, event)
        row = self.connection.execute(
            "SELECT correlation_id, details_json FROM audit_events WHERE event_id = ?",
            (event["event_id"],),
        ).fetchone()
        details = json.loads(row["details_json"])
        self.assertEqual(row["correlation_id"], "corr-1")
        self.assertEqual(details["password"], "[REDACTED]")
        self.assertEqual(details["safe"], "visible")
        self.assertNotIn("never-store", row["details_json"])


if __name__ == "__main__":
    unittest.main()
