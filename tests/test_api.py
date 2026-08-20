from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from api.server import (  # noqa: E402
    ManifestError,
    load_manifest,
    make_handler,
    normalize_correlation_id,
    validate_manifest,
)


class ApiServerMixin:
    manifest_path: Path
    server: ThreadingHTTPServer
    thread: threading.Thread

    def start_server(self, manifest_path: Path) -> None:
        self.manifest_path = manifest_path
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(manifest_path))
        self.server.daemon_threads = True
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def stop_server(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def request(self, method: str, path: str, headers: dict[str, str] | None = None):
        host, port = self.server.server_address
        conn = HTTPConnection(host, port, timeout=3)
        conn.request(method, path, headers=headers or {})
        response = conn.getresponse()
        body = response.read()
        result_headers = {k.lower(): v for k, v in response.getheaders()}
        status = response.status
        conn.close()
        content_type = result_headers.get("content-type", "")
        if not body:
            payload = None
        elif content_type.startswith("application/json"):
            payload = json.loads(body.decode("utf-8"))
        else:
            payload = body.decode("utf-8")
        return status, result_headers, payload


class ManifestTests(unittest.TestCase):
    def test_repository_manifest_is_valid(self) -> None:
        manifest = load_manifest(ROOT / "deployment.json")
        self.assertEqual(manifest["schema"], 1)
        self.assertEqual(manifest["product"], "control-center")

    def test_invalid_manifest_is_rejected(self) -> None:
        with self.assertRaises(ManifestError):
            validate_manifest({"schema": 2, "product": "control-center"})

    def test_correlation_id_accepts_bounded_safe_value(self) -> None:
        self.assertEqual(normalize_correlation_id("cc-test_01:abc"), "cc-test_01:abc")

    def test_correlation_id_replaces_unsafe_value(self) -> None:
        result = normalize_correlation_id("bad value with spaces")
        self.assertNotEqual(result, "bad value with spaces")
        self.assertGreater(len(result), 10)


class ApiTests(ApiServerMixin, unittest.TestCase):
    def setUp(self) -> None:
        self.start_server(ROOT / "deployment.json")

    def tearDown(self) -> None:
        self.stop_server()

    def test_health(self) -> None:
        status, headers, payload = self.request("GET", "/api/v1/health")
        self.assertEqual(status, 200)
        self.assertEqual(payload["status"], "ok")
        self.assertEqual(payload["api_version"], 1)
        self.assertEqual(headers["cache-control"], "no-store")
        self.assertEqual(headers["x-frame-options"], "DENY")
        self.assertIn("x-correlation-id", headers)

    def test_readiness(self) -> None:
        status, _, payload = self.request("GET", "/api/v1/readiness")
        self.assertEqual(status, 200)
        self.assertEqual(payload["status"], "ready")
        self.assertEqual(payload["checks"]["deployment_manifest"], "ok")

    def test_version(self) -> None:
        status, headers, payload = self.request(
            "GET",
            "/api/v1/version?ignored=query",
            {"X-Correlation-ID": "test-request-01"},
        )
        self.assertEqual(status, 200)
        self.assertEqual(payload["product"], "control-center")
        self.assertEqual(headers["x-correlation-id"], "test-request-01")

    def test_release_contract(self) -> None:
        status, _, payload = self.request("GET", "/api/v1/release")
        self.assertEqual(status, 200)
        self.assertEqual(
            set(payload),
            {"schema", "product", "updated_at", "release", "features", "clients"},
        )

    def test_unknown_endpoint_is_bounded_404(self) -> None:
        status, _, payload = self.request("GET", "/api/v1/unknown")
        self.assertEqual(status, 404)
        self.assertEqual(payload["error"]["code"], "not_found")
        self.assertIn("correlation_id", payload["error"])

    def test_write_method_is_rejected(self) -> None:
        status, headers, payload = self.request("POST", "/api/v1/release")
        self.assertEqual(status, 405)
        self.assertEqual(headers["allow"], "GET, HEAD")
        self.assertEqual(payload["error"]["code"], "method_not_allowed")

    def test_head_has_no_body(self) -> None:
        status, _, payload = self.request("HEAD", "/api/v1/health")
        self.assertEqual(status, 200)
        self.assertIsNone(payload)

    def test_web_ui_shell_contains_canonical_navigation(self) -> None:
        status, headers, body = self.request("GET", "/overview")
        self.assertEqual(status, 200)
        self.assertTrue(headers["content-type"].startswith("text/html"))
        self.assertEqual(headers["x-frame-options"], "DENY")
        self.assertIn("default-src 'none'", headers["content-security-policy"])
        for label in ("Обзор", "Маркет", "RBAC", "Система"):
            self.assertIn(label, body)
        self.assertNotIn("<script", body.lower())
        self.assertNotIn("<form", body.lower())

    def test_all_web_ui_routes_are_read_only_pages(self) -> None:
        for path in ("/", "/overview", "/market", "/rbac", "/system"):
            with self.subTest(path=path):
                status, _, body = self.request("GET", path)
                self.assertEqual(status, 200)
                self.assertIn("Control Center", body)

    def test_ui_head_has_no_body(self) -> None:
        status, _, payload = self.request("HEAD", "/system")
        self.assertEqual(status, 200)
        self.assertIsNone(payload)


class NotReadyTests(ApiServerMixin, unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        invalid_path = Path(self.tmp.name) / "deployment.json"
        invalid_path.write_text('{"schema":2}', encoding="utf-8")
        self.start_server(invalid_path)

    def tearDown(self) -> None:
        self.stop_server()
        self.tmp.cleanup()

    def test_readiness_fails_closed(self) -> None:
        status, _, payload = self.request("GET", "/api/v1/readiness")
        self.assertEqual(status, 503)
        self.assertEqual(payload["status"], "not_ready")

    def test_version_fails_closed(self) -> None:
        status, _, payload = self.request("GET", "/api/v1/version")
        self.assertEqual(status, 503)
        self.assertEqual(payload["error"]["code"], "service_not_ready")

    def test_web_ui_fails_closed(self) -> None:
        status, headers, body = self.request("GET", "/overview")
        self.assertEqual(status, 503)
        self.assertTrue(headers["content-type"].startswith("text/html"))
        self.assertIn("временно недоступен", body)
        self.assertNotIn("<script", body.lower())


if __name__ == "__main__":
    unittest.main()
