import io
import json
import unittest
from contextlib import redirect_stderr
from urllib.error import HTTPError
from urllib.request import Request

from scripts import ai_gateway


class _Response:
    def __init__(self, payload: bytes):
        self.payload = payload

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False

    def read(self, limit: int = -1) -> bytes:
        return self.payload if limit < 0 else self.payload[:limit]


class AIGatewayTests(unittest.TestCase):
    def test_rejects_non_https_and_non_allowlisted_hosts(self):
        with self.assertRaises(ValueError):
            ai_gateway.post_json(
                "http://api.example.com/v1",
                {},
                {},
                provider="Example",
                allowed_hosts={"api.example.com"},
                timeout=10,
            )
        with self.assertRaises(ValueError):
            ai_gateway.post_json(
                "https://evil.example/v1",
                {},
                {},
                provider="Example",
                allowed_hosts={"api.example.com"},
                timeout=10,
            )
        with self.assertRaises(ValueError):
            ai_gateway.post_json(
                "https://user:pass@api.example.com/v1",
                {},
                {},
                provider="Example",
                allowed_hosts={"api.example.com"},
                timeout=10,
            )

    def test_rejects_redirects_before_crossing_provider_trust_boundary(self):
        request = Request(
            "https://api.example.com/v1",
            data=b"{}",
            headers={"Authorization": "Bearer secret"},
            method="POST",
        )
        handler = ai_gateway._RejectRedirectHandler()
        with self.assertRaises(HTTPError) as raised:
            handler.redirect_request(
                request,
                io.BytesIO(b""),
                302,
                "Found",
                {},
                "https://evil.example/collect",
            )
        self.assertEqual(raised.exception.code, 302)
        self.assertNotIn("evil.example", str(raised.exception))

    def test_provider_headers_are_not_redirectable(self):
        captured = {}

        def opener(request, timeout):
            captured["headers"] = dict(request.headers)
            captured["unredirected"] = dict(request.unredirected_hdrs)
            return _Response(b'{"ok":true}')

        result = ai_gateway.post_json(
            "https://api.example.com/v1",
            {"request": "value"},
            {"Authorization": "Bearer secret", "X-Api-Key": "secret-key"},
            provider="Example",
            allowed_hosts={"api.example.com"},
            timeout=10,
            opener=opener,
        )
        self.assertEqual(result, {"ok": True})
        self.assertEqual(captured["headers"], {"Content-type": "application/json"})
        self.assertNotIn("Authorization", captured["headers"])
        self.assertNotIn("X-api-key", captured["headers"])
        self.assertEqual(captured["unredirected"].get("Authorization"), "Bearer secret")
        self.assertEqual(captured["unredirected"].get("X-api-key"), "secret-key")

    def test_returns_only_json_objects(self):
        payload = json.dumps({"ok": True}).encode()
        result = ai_gateway.post_json(
            "https://api.example.com/v1",
            {"request": "value"},
            {"Authorization": "Bearer secret"},
            provider="Example",
            allowed_hosts={"api.example.com"},
            timeout=10,
            opener=lambda request, timeout: _Response(payload),
        )
        self.assertEqual(result, {"ok": True})

        with self.assertRaises(ai_gateway.ProviderResponseError):
            ai_gateway.post_json(
                "https://api.example.com/v1",
                {},
                {},
                provider="Example",
                allowed_hosts={"api.example.com"},
                timeout=10,
                opener=lambda request, timeout: _Response(b"[]"),
            )

    def test_response_size_is_bounded(self):
        with self.assertRaises(ai_gateway.ProviderResponseError):
            ai_gateway.post_json(
                "https://api.example.com/v1",
                {},
                {},
                provider="Example",
                allowed_hosts={"api.example.com"},
                timeout=10,
                max_response_bytes=8,
                opener=lambda request, timeout: _Response(b'{"value":"too-large"}'),
            )

    def test_transient_http_retry_does_not_log_upstream_body(self):
        calls = []

        def opener(request, timeout):
            calls.append(request)
            if len(calls) == 1:
                raise HTTPError(
                    request.full_url,
                    429,
                    "Too Many Requests",
                    hdrs=None,
                    fp=io.BytesIO(b"SECRET-ECHOED-UPSTREAM-BODY"),
                )
            return _Response(b'{"ok":true}')

        stderr = io.StringIO()
        with redirect_stderr(stderr):
            result = ai_gateway.post_json(
                "https://api.example.com/v1",
                {"private": "request"},
                {"Authorization": "Bearer top-secret"},
                provider="Example",
                allowed_hosts={"api.example.com"},
                timeout=10,
                opener=opener,
                sleeper=lambda delay: None,
                jitter=lambda low, high: 0.0,
            )
        self.assertEqual(result, {"ok": True})
        self.assertEqual(len(calls), 2)
        self.assertIn("transient failure", stderr.getvalue())
        self.assertNotIn("SECRET-ECHOED-UPSTREAM-BODY", stderr.getvalue())
        self.assertNotIn("top-secret", stderr.getvalue())

    def test_limits_are_validated(self):
        for kwargs in (
            {"timeout": 0},
            {"timeout": 10, "max_attempts": 0},
            {"timeout": 10, "max_response_bytes": 0},
        ):
            with self.subTest(kwargs=kwargs):
                with self.assertRaises(ValueError):
                    ai_gateway.post_json(
                        "https://api.example.com/v1",
                        {},
                        {},
                        provider="Example",
                        allowed_hosts={"api.example.com"},
                        **kwargs,
                    )


if __name__ == "__main__":
    unittest.main()
