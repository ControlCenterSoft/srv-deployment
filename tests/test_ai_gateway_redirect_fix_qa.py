import io
import unittest
import urllib.request
from email.message import Message

from scripts import ai_gateway


class _Response:
    def __init__(self, url: str, code: int, *, headers=None, body: bytes = b"", msg: str = "OK"):
        self.url = url
        self.code = code
        self.status = code
        self.msg = msg
        self.headers = headers or Message()
        self._body = io.BytesIO(body)

    def read(self, limit: int = -1) -> bytes:
        return self._body.read(limit)

    def info(self):
        return self.headers

    def geturl(self) -> str:
        return self.url

    def close(self) -> None:
        pass

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        self.close()
        return False


class _FakeHTTPSHandler(urllib.request.HTTPSHandler):
    def __init__(self, seen, *, redirect_code: int, redirect_target: str):
        super().__init__()
        self.seen = seen
        self.redirect_code = redirect_code
        self.redirect_target = redirect_target

    def https_open(self, request):
        self.seen.append((request.full_url, {key.lower(): value for key, value in request.header_items()}))
        if request.full_url == "https://api.example.com/v1":
            headers = Message()
            headers["Location"] = self.redirect_target
            return _Response(request.full_url, self.redirect_code, headers=headers, msg="Redirect")
        return _Response(request.full_url, 200, body=b'{"ok":true}')


class _FakeHTTPHandler(urllib.request.HTTPHandler):
    def __init__(self, seen):
        super().__init__()
        self.seen = seen

    def http_open(self, request):
        self.seen.append((request.full_url, {key.lower(): value for key, value in request.header_items()}))
        return _Response(request.full_url, 200, body=b'{"ok":true}')


class AIGatewayRedirectFixQATests(unittest.TestCase):
    def _assert_default_transport_rejects_redirect(self, code: int, target: str) -> None:
        seen = []
        opener = urllib.request.build_opener(
            ai_gateway._RejectRedirectHandler(),
            _FakeHTTPSHandler(seen, redirect_code=code, redirect_target=target),
            _FakeHTTPHandler(seen),
        )
        previous = ai_gateway._NO_REDIRECT_OPENER
        ai_gateway._NO_REDIRECT_OPENER = opener
        try:
            with self.assertRaises(ai_gateway.ProviderTransportError) as raised:
                ai_gateway.post_json(
                    "https://api.example.com/v1",
                    {"private": "request"},
                    {
                        "Authorization": "Bearer qa-secret",
                        "X-Api-Key": "qa-key",
                    },
                    provider="Example",
                    allowed_hosts={"api.example.com"},
                    timeout=10,
                    max_attempts=1,
                )
        finally:
            ai_gateway._NO_REDIRECT_OPENER = previous

        self.assertEqual([url for url, _headers in seen], ["https://api.example.com/v1"])
        initial_headers = seen[0][1]
        self.assertEqual(initial_headers.get("authorization"), "Bearer qa-secret")
        self.assertEqual(initial_headers.get("x-api-key"), "qa-key")
        message = str(raised.exception)
        self.assertNotIn(target, message)
        self.assertNotIn("qa-secret", message)
        self.assertNotIn("qa-key", message)

    def test_cross_host_https_redirect_is_rejected_before_second_request(self):
        self._assert_default_transport_rejects_redirect(302, "https://evil.example/capture")

    def test_https_to_http_redirect_is_rejected_before_second_request(self):
        self._assert_default_transport_rejects_redirect(307, "http://evil.example/capture")

    def test_same_host_redirect_is_rejected_fail_closed(self):
        self._assert_default_transport_rejects_redirect(308, "https://api.example.com/other")


if __name__ == "__main__":
    unittest.main()
