import io
import unittest
from email.message import Message
from urllib.error import HTTPError

from scripts import ai_gateway
from tests.test_ai_gateway_redirect_fix_qa import AIGatewayRedirectFixQATests


class AIGatewayTransportMatrixQATests(AIGatewayRedirectFixQATests):
    def test_301_redirect_is_rejected_before_second_request(self):
        self._assert_default_transport_rejects_redirect(301, "https://evil.example/capture")

    def test_303_redirect_is_rejected_before_second_request(self):
        self._assert_default_transport_rejects_redirect(303, "https://evil.example/capture")

    def test_provider_http_error_body_is_not_reflected(self):
        provider_body = b"provider-controlled-secret-body"

        def opener(request, timeout):
            raise HTTPError(
                request.full_url,
                400,
                "Bad Request",
                Message(),
                io.BytesIO(provider_body),
            )

        with self.assertRaises(ai_gateway.ProviderTransportError) as raised:
            ai_gateway.post_json(
                "https://api.example.com/v1",
                {"private": "request"},
                {"Authorization": "Bearer qa-secret"},
                provider="Example",
                allowed_hosts={"api.example.com"},
                timeout=10,
                max_attempts=1,
                opener=opener,
            )

        message = str(raised.exception)
        self.assertNotIn(provider_body.decode(), message)
        self.assertNotIn("qa-secret", message)
        self.assertEqual(message, "Example API HTTP 400")


if __name__ == "__main__":
    unittest.main()
