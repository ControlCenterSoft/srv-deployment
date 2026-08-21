#!/usr/bin/env python3
"""Shared hardened HTTP transport for advisory AI provider integrations.

This module is intentionally transport-only. Provider request/response semantics stay in
provider adapters so Core and UX code never depend on provider-specific behavior.
"""

from __future__ import annotations

import json
import random
import sys
import time
from collections.abc import Callable, Collection, Mapping
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener

TRANSIENT_HTTP_CODES = frozenset({408, 429, 500, 502, 503, 504})
DEFAULT_MAX_RESPONSE_BYTES = 2_000_000
MAX_ATTEMPTS_LIMIT = 6
MAX_TIMEOUT_SECONDS = 300
MAX_RESPONSE_BYTES_LIMIT = 4_000_000


class ProviderTransportError(RuntimeError):
    """A provider request failed before a valid JSON object was obtained."""


class ProviderResponseError(ValueError):
    """A provider returned an invalid or unsafe response envelope."""


class _RejectRedirectHandler(HTTPRedirectHandler):
    """Fail closed on redirects so provider data and credentials never cross trust boundaries."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise HTTPError(
            req.full_url,
            code,
            "provider redirects are not allowed",
            headers,
            fp,
        )


_NO_REDIRECT_OPENER = build_opener(_RejectRedirectHandler())


def _open_no_redirect(request: Request, timeout: int):
    return _NO_REDIRECT_OPENER.open(request, timeout=timeout)


def _validate_endpoint(endpoint: str, allowed_hosts: Collection[str]) -> str:
    parsed = urlparse(endpoint)
    host = (parsed.hostname or "").lower()
    normalized_hosts = {item.lower() for item in allowed_hosts}
    if parsed.scheme != "https":
        raise ValueError("provider endpoint must use https")
    if not host or host not in normalized_hosts:
        raise ValueError("provider endpoint host is not allowlisted")
    if parsed.username is not None or parsed.password is not None:
        raise ValueError("provider endpoint must not contain userinfo")
    if parsed.port not in {None, 443}:
        raise ValueError("provider endpoint must use the default HTTPS port")
    return endpoint


def _validate_limits(timeout: int, max_attempts: int, max_response_bytes: int) -> None:
    if isinstance(timeout, bool) or not isinstance(timeout, int) or not 1 <= timeout <= MAX_TIMEOUT_SECONDS:
        raise ValueError(f"timeout must be an integer in 1..{MAX_TIMEOUT_SECONDS}")
    if (
        isinstance(max_attempts, bool)
        or not isinstance(max_attempts, int)
        or not 1 <= max_attempts <= MAX_ATTEMPTS_LIMIT
    ):
        raise ValueError(f"max_attempts must be an integer in 1..{MAX_ATTEMPTS_LIMIT}")
    if (
        isinstance(max_response_bytes, bool)
        or not isinstance(max_response_bytes, int)
        or not 1 <= max_response_bytes <= MAX_RESPONSE_BYTES_LIMIT
    ):
        raise ValueError(
            f"max_response_bytes must be an integer in 1..{MAX_RESPONSE_BYTES_LIMIT}"
        )


def retry_delay(attempt: int, jitter: Callable[[float, float], float] = random.uniform) -> float:
    """Bounded exponential backoff with jitter for transient provider failures."""
    return min(8.0, float(2**attempt)) + jitter(0.0, 0.5)


def _decode_json_object(raw: bytes, provider: str) -> dict[str, Any]:
    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ProviderResponseError(f"{provider} response was not valid UTF-8 JSON") from exc
    if not isinstance(payload, dict):
        raise ProviderResponseError(f"{provider} response must be a JSON object")
    return payload


def post_json(
    endpoint: str,
    body: Mapping[str, Any],
    headers: Mapping[str, str],
    *,
    provider: str,
    allowed_hosts: Collection[str],
    timeout: int,
    max_attempts: int = 4,
    max_response_bytes: int = DEFAULT_MAX_RESPONSE_BYTES,
    opener: Callable[..., Any] = _open_no_redirect,
    sleeper: Callable[[float], None] = time.sleep,
    jitter: Callable[[float, float], float] = random.uniform,
) -> dict[str, Any]:
    """POST one bounded JSON request with allowlisted HTTPS transport and transient retries.

    Provider redirects are rejected. Provider-supplied headers are added as unredirected
    headers as defense in depth, so credentials are never copied to a redirected request if
    redirect behavior is changed later. Provider response bodies are never copied into error
    messages, preventing untrusted upstream payloads from leaking submitted diffs, prompts,
    credentials, or other sensitive material into CI logs.
    """

    provider_name = str(provider).strip() or "Provider"
    safe_endpoint = _validate_endpoint(endpoint, allowed_hosts)
    _validate_limits(timeout, max_attempts, max_response_bytes)
    encoded = json.dumps(dict(body), ensure_ascii=False).encode("utf-8")

    last_error: Exception | None = None
    for attempt in range(max_attempts):
        request = Request(
            safe_endpoint,
            data=encoded,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        for name, value in dict(headers).items():
            request.add_unredirected_header(name, value)
        try:
            with opener(request, timeout=timeout) as response:
                raw = response.read(max_response_bytes + 1)
                if len(raw) > max_response_bytes:
                    raise ProviderResponseError(
                        f"{provider_name} response exceeded {max_response_bytes} bytes"
                    )
                return _decode_json_object(raw, provider_name)
        except ProviderResponseError:
            raise
        except HTTPError as exc:
            last_error = ProviderTransportError(f"{provider_name} API HTTP {exc.code}")
            if exc.code not in TRANSIENT_HTTP_CODES or attempt + 1 >= max_attempts:
                raise last_error from exc
        except URLError as exc:
            last_error = ProviderTransportError(f"{provider_name} API request failed")
            if attempt + 1 >= max_attempts:
                raise last_error from exc

        delay = retry_delay(attempt, jitter)
        print(
            f"{provider_name} transient failure; retrying attempt {attempt + 2}/{max_attempts} "
            f"after {delay:.1f}s",
            file=sys.stderr,
        )
        sleeper(delay)

    raise ProviderTransportError(f"{provider_name} API request failed: {last_error}")
