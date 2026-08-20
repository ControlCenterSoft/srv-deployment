from __future__ import annotations

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from api.audit import build_audit_event, sanitize_audit_value  # noqa: E402
from api.rbac import Permission, Role, is_allowed, public_policy, require_permission  # noqa: E402
from api.security import (  # noqa: E402
    PasswordPolicyError,
    hash_password,
    hash_session_token,
    issue_session_token,
    secure_session_cookie,
    validate_password,
    verify_password,
)


class RbacTests(unittest.TestCase):
    def test_viewer_is_read_only(self) -> None:
        self.assertTrue(is_allowed(Role.VIEWER, Permission.ACCOUNT_READ))
        self.assertTrue(is_allowed(Role.VIEWER, Permission.SERVER_READ))
        self.assertFalse(is_allowed(Role.VIEWER, Permission.ADMIN_USERS_READ))
        self.assertFalse(is_allowed(Role.VIEWER, Permission.ACCOUNT_SESSION_REVOKE))

    def test_admin_has_every_declared_permission(self) -> None:
        for permission in Permission:
            with self.subTest(permission=permission.value):
                self.assertTrue(is_allowed(Role.ADMIN, permission))

    def test_require_permission_fails_closed(self) -> None:
        with self.assertRaises(PermissionError):
            require_permission(Role.VIEWER, Permission.ADMIN_AUDIT_READ)

    def test_public_policy_uses_stable_string_contract(self) -> None:
        policy = public_policy()
        self.assertEqual(set(policy), {"viewer", "admin"})
        self.assertIn("admin.audit.read", policy["admin"])
        self.assertNotIn("admin.audit.read", policy["viewer"])


class PasswordTests(unittest.TestCase):
    def test_password_policy_rejects_short_and_nul(self) -> None:
        with self.assertRaises(PasswordPolicyError):
            validate_password("short")
        with self.assertRaises(PasswordPolicyError):
            validate_password("valid-length\x00but-nul")

    def test_password_hash_round_trip(self) -> None:
        password = "Correct Horse Battery Staple 2026!"
        encoded = hash_password(password)
        self.assertTrue(encoded.startswith("scrypt$"))
        self.assertNotIn(password, encoded)
        self.assertTrue(verify_password(password, encoded))
        self.assertFalse(verify_password(password + "x", encoded))

    def test_malformed_or_unbounded_hash_parameters_fail_closed(self) -> None:
        self.assertFalse(verify_password("anything-long-enough", "not-a-hash"))
        self.assertFalse(
            verify_password(
                "anything-long-enough",
                "scrypt$1048576$8$1$c2FsdA$ZGlnaWVzdA",
            )
        )


class SessionTests(unittest.TestCase):
    def test_session_token_is_random_and_only_digest_is_for_storage(self) -> None:
        first = issue_session_token()
        second = issue_session_token()
        self.assertNotEqual(first, second)
        digest = hash_session_token(first)
        self.assertEqual(len(digest), 64)
        self.assertNotIn(first, digest)

    def test_cookie_is_host_scoped_secure_and_http_only(self) -> None:
        token = issue_session_token()
        cookie = secure_session_cookie(token, 3600)
        self.assertTrue(cookie.startswith("__Host-cc_session="))
        self.assertIn("Path=/", cookie)
        self.assertIn("Secure", cookie)
        self.assertIn("HttpOnly", cookie)
        self.assertIn("SameSite=Strict", cookie)
        self.assertNotIn("Domain=", cookie)

    def test_cookie_rejects_invalid_token_and_lifetime(self) -> None:
        with self.assertRaises(ValueError):
            secure_session_cookie("bad token", 3600)
        with self.assertRaises(ValueError):
            secure_session_cookie(issue_session_token(), 10)


class AuditTests(unittest.TestCase):
    def test_sensitive_keys_are_redacted_recursively(self) -> None:
        sanitized = sanitize_audit_value(
            {
                "user": "admin",
                "password": "never-log-this",
                "nested": {
                    "Authorization": "Bearer secret",
                    "api_key": "secret-key",
                    "safe": "visible",
                },
                "cookies": "session=secret",
            }
        )
        self.assertEqual(sanitized["password"], "[REDACTED]")
        self.assertEqual(sanitized["nested"]["Authorization"], "[REDACTED]")
        self.assertEqual(sanitized["nested"]["api_key"], "[REDACTED]")
        self.assertEqual(sanitized["cookies"], "[REDACTED]")
        self.assertEqual(sanitized["nested"]["safe"], "visible")

    def test_audit_event_has_correlation_and_no_raw_secret(self) -> None:
        event = build_audit_event(
            correlation_id="request-123",
            actor_id="admin",
            role="admin",
            action="session.login",
            outcome="success",
            details={"session_token": "raw-secret", "source": "web"},
        )
        self.assertEqual(event["schema"], 1)
        self.assertEqual(event["correlation_id"], "request-123")
        self.assertEqual(event["details"]["session_token"], "[REDACTED]")
        self.assertNotIn("raw-secret", str(event))


if __name__ == "__main__":
    unittest.main()
