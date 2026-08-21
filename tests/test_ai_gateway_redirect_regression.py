import io
import unittest
import urllib.request
from email.message import Message

from scripts import ai_gateway


class _Response:
    def __init__(self, url: str, code: int, body: bytes = b"", headers=None, msg: str = "OK"):
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
    def __init__(self, seen, redirect_target: str):
        super().__init__()
        self.seen = seen
        self.redirect_target = redirect_target

    def https_open(self, request):
        self.seen.append((request.full_url, {k.lower(): v for k, v in request.header_items()}))
        if request.full_url == "https://api.example.com/v1":
            headers = Message()
            headers["Location"] = self.redirect_target
            return _Response(request.full_url, 302, headers=headers, msg="Found")
        return _Response(request.full_url, 200, body=b'{"ok":true}')


class _FakeHTTPHandler(urllib.request.HTTPHandler):
    def __init__(self, seen):
        super().__init__()
        self.seen = seen

    def http_open(self, request):
        self.seen.append((request.full_url, {k.lower(): v for k, v in request.header_items()}))
        return _Response(request.full_url, 200, body=b'{"ok":true}')


class AIGatewayRedirectRegressionTests(unittest.TestCase):
    def _assert_redirect_is_rejected_before_second_request(self, target: str) -> None:
        seen = []
        opener = urllib.request.build_opener(
            _FakeHTTPSHandler(seen, target),
            _FakeHTTPHandler(seen),
        )
        previous = getattr(urllib.request, "_opener", None)
        urllib.request.install_opener(opener)
        try:
            with self.assertRaises((ai_gateway.ProviderTransportError, ValueError)):
                ai_gateway.post_json(
                    "https://api.example.com/v1",
                    {"private": "request"},
                    {
                        "Authorization": "Bearer top-secret",
                        "x-goog-api-key": "gemini-secret",
                    },
                    provider="Example",
                    allowed_hosts={"api.example.com"},
                    timeout=10,
                )
        finally:
            urllib.request._opener = previous

        self.assertEqual(
            [url for url, _headers in seen],
            ["https://api.example.com/v1"],
            "the transport must reject a redirect target before issuing a second request",
        )
        for _url, headers in seen:
            self.assertNotEqual(headers.get("authorization"), "Bearer top-secret") if _url != "https://api.example.com/v1" else None
            self.assertNotEqual(headers.get("x-goog-api-key"), "gemini-secret") if _url != "https://api.example.com/v1" else None

    def test_cross_host_https_redirect_cannot_escape_allowlist(self):
        self._assert_redirect_is_rejected_before_second_request("https://evil.example/capture")

    def test_https_to_http_redirect_cannot_downgrade_transport(self):
        self._assert_redirect_is_rejected_before_second_request("http://evil.example/capture")


if __name__ == "__main__":
    unittest.main()
