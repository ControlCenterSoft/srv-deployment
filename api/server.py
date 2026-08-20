#!/usr/bin/env python3
"""Базовая реализация read-only Web UI и Platform API v1 Control Center.

Начальный сервис намеренно открывает только ограниченные endpoints для чтения.
Привилегированные операции будут добавлены позже за server-side RBAC и аудитом.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import uuid
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

try:
    from .ui import UI_PATHS, render_ui
except ImportError:  # Прямой запуск: python3 api/server.py
    from ui import UI_PATHS, render_ui

API_VERSION = 1
SERVICE_NAME = "control-center-api"
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8876
DEFAULT_MANIFEST = Path(__file__).resolve().parents[1] / "deployment.json"
CORRELATION_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$")


class ManifestError(ValueError):
    """Ошибка отсутствующих или некорректных deployment metadata."""


def validate_manifest(data: Any) -> dict[str, Any]:
    if not isinstance(data, dict):
        raise ManifestError("deployment manifest должен быть объектом")
    if data.get("schema") != 1:
        raise ManifestError("deployment schema должна быть равна 1")
    if data.get("product") != "control-center":
        raise ManifestError("deployment product должен быть control-center")

    release = data.get("release")
    if not isinstance(release, dict):
        raise ManifestError("release должен быть объектом")
    for field in ("version", "channel", "status", "acceptance"):
        value = release.get(field)
        if not isinstance(value, str) or not value.strip():
            raise ManifestError(f"release.{field} должен быть непустой строкой")

    features = data.get("features")
    if not isinstance(features, list):
        raise ManifestError("features должен быть массивом")
    for index, feature in enumerate(features):
        if not isinstance(feature, dict):
            raise ManifestError(f"features[{index}] должен быть объектом")
        for field in ("id", "status"):
            value = feature.get(field)
            if not isinstance(value, str) or not value.strip():
                raise ManifestError(f"features[{index}].{field} должен быть непустой строкой")

    clients = data.get("clients")
    if not isinstance(clients, dict):
        raise ManifestError("clients должен быть объектом")
    for name, client in clients.items():
        if not isinstance(name, str) or not name:
            raise ManifestError("имена clients должны быть непустыми строками")
        if not isinstance(client, dict):
            raise ManifestError(f"clients.{name} должен быть объектом")
        for field in ("version", "status"):
            value = client.get(field)
            if not isinstance(value, str) or not value.strip():
                raise ManifestError(f"clients.{name}.{field} должен быть непустой строкой")

    return data


def load_manifest(path: str | Path | None = None) -> dict[str, Any]:
    manifest_path = Path(
        path
        or os.environ.get("CONTROL_CENTER_DEPLOYMENT_MANIFEST")
        or DEFAULT_MANIFEST
    )
    try:
        payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ManifestError(f"не удалось загрузить deployment manifest: {exc}") from exc
    return validate_manifest(payload)


def normalize_correlation_id(value: str | None) -> str:
    if value and CORRELATION_ID_RE.fullmatch(value):
        return value
    return str(uuid.uuid4())


def public_release_payload(manifest: dict[str, Any]) -> dict[str, Any]:
    """Вернуть только явно публичный контракт deployment metadata."""
    return {
        "schema": manifest["schema"],
        "product": manifest["product"],
        "updated_at": manifest.get("updated_at"),
        "release": manifest["release"],
        "features": manifest["features"],
        "clients": manifest["clients"],
    }


def version_payload(manifest: dict[str, Any]) -> dict[str, Any]:
    release = manifest["release"]
    return {
        "service": SERVICE_NAME,
        "api_version": API_VERSION,
        "product": manifest["product"],
        "version": release["version"],
        "channel": release["channel"],
        "status": release["status"],
        "acceptance": release["acceptance"],
        "source_sha": os.environ.get("CONTROL_CENTER_SOURCE_SHA"),
    }


class ControlCenterRequestHandler(BaseHTTPRequestHandler):
    server_version = "ControlCenterAPI/1"
    sys_version = ""
    manifest_path: str | Path | None = None

    def log_message(self, _format: str, *args: object) -> None:
        # Намеренно подавляем стандартный журнал запросов BaseHTTPRequestHandler,
        # чтобы query string случайно не стал каналом утечки секретов в лог.
        return

    def _common_headers(self, correlation_id: str) -> None:
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Correlation-ID", correlation_id)

    def _send_json(
        self,
        status: HTTPStatus,
        payload: dict[str, Any],
        correlation_id: str,
        *,
        send_body: bool,
        allow: str | None = None,
    ) -> None:
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status.value)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self._common_headers(correlation_id)
        if allow:
            self.send_header("Allow", allow)
        self.end_headers()
        if send_body:
            self.wfile.write(body)

    def _send_html(
        self,
        status: HTTPStatus,
        document: str,
        correlation_id: str,
        *,
        send_body: bool,
    ) -> None:
        body = document.encode("utf-8")
        self.send_response(status.value)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header(
            "Content-Security-Policy",
            "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; "
            "form-action 'none'; frame-ancestors 'none'",
        )
        self._common_headers(correlation_id)
        self.end_headers()
        if send_body:
            self.wfile.write(body)

    def _error(
        self,
        status: HTTPStatus,
        code: str,
        message: str,
        correlation_id: str,
        *,
        send_body: bool,
        allow: str | None = None,
    ) -> None:
        self._send_json(
            status,
            {
                "error": {
                    "code": code,
                    "message": message,
                    "correlation_id": correlation_id,
                }
            },
            correlation_id,
            send_body=send_body,
            allow=allow,
        )

    def _route(self, *, send_body: bool) -> None:
        correlation_id = normalize_correlation_id(self.headers.get("X-Correlation-ID"))
        path = urlsplit(self.path).path

        if path in UI_PATHS:
            try:
                manifest = load_manifest(self.manifest_path)
            except ManifestError:
                self._send_html(
                    HTTPStatus.SERVICE_UNAVAILABLE,
                    "<!doctype html><html lang=\"ru\"><meta charset=\"utf-8\">"
                    "<title>Control Center недоступен</title>"
                    "<body><h1>Control Center временно недоступен</h1>"
                    "<p>Метаданные deployment не прошли проверку готовности.</p></body></html>",
                    correlation_id,
                    send_body=send_body,
                )
                return
            self._send_html(
                HTTPStatus.OK,
                render_ui(path, manifest),
                correlation_id,
                send_body=send_body,
            )
            return

        if path == "/api/v1/health":
            self._send_json(
                HTTPStatus.OK,
                {
                    "status": "ok",
                    "service": SERVICE_NAME,
                    "api_version": API_VERSION,
                },
                correlation_id,
                send_body=send_body,
            )
            return

        if path == "/api/v1/readiness":
            try:
                manifest = load_manifest(self.manifest_path)
            except ManifestError:
                self._send_json(
                    HTTPStatus.SERVICE_UNAVAILABLE,
                    {
                        "status": "not_ready",
                        "service": SERVICE_NAME,
                        "checks": {"deployment_manifest": "failed"},
                    },
                    correlation_id,
                    send_body=send_body,
                )
                return
            self._send_json(
                HTTPStatus.OK,
                {
                    "status": "ready",
                    "service": SERVICE_NAME,
                    "checks": {"deployment_manifest": "ok"},
                    "release": manifest["release"]["version"],
                },
                correlation_id,
                send_body=send_body,
            )
            return

        if path in {"/api/v1/version", "/api/v1/release"}:
            try:
                manifest = load_manifest(self.manifest_path)
            except ManifestError:
                self._error(
                    HTTPStatus.SERVICE_UNAVAILABLE,
                    "service_not_ready",
                    "Метаданные deployment недоступны или некорректны",
                    correlation_id,
                    send_body=send_body,
                )
                return
            payload = (
                version_payload(manifest)
                if path == "/api/v1/version"
                else public_release_payload(manifest)
            )
            self._send_json(
                HTTPStatus.OK,
                payload,
                correlation_id,
                send_body=send_body,
            )
            return

        self._error(
            HTTPStatus.NOT_FOUND,
            "not_found",
            "Endpoint не найден",
            correlation_id,
            send_body=send_body,
        )

    def do_GET(self) -> None:  # noqa: N802 — API HTTP-обработчика stdlib
        self._route(send_body=True)

    def do_HEAD(self) -> None:  # noqa: N802 — API HTTP-обработчика stdlib
        self._route(send_body=False)

    def _method_not_allowed(self) -> None:
        correlation_id = normalize_correlation_id(self.headers.get("X-Correlation-ID"))
        self._error(
            HTTPStatus.METHOD_NOT_ALLOWED,
            "method_not_allowed",
            "В текущей базовой линии разрешены только GET и HEAD",
            correlation_id,
            send_body=True,
            allow="GET, HEAD",
        )

    do_POST = _method_not_allowed  # type: ignore[assignment]
    do_PUT = _method_not_allowed  # type: ignore[assignment]
    do_PATCH = _method_not_allowed  # type: ignore[assignment]
    do_DELETE = _method_not_allowed  # type: ignore[assignment]


def make_handler(manifest_path: str | Path | None = None) -> type[ControlCenterRequestHandler]:
    class Handler(ControlCenterRequestHandler):
        pass

    Handler.manifest_path = manifest_path
    return Handler


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Web UI и Platform API v1 Control Center")
    parser.add_argument(
        "--host",
        default=os.environ.get("CONTROL_CENTER_API_HOST", DEFAULT_HOST),
        help=f"адрес прослушивания (по умолчанию: {DEFAULT_HOST})",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=int(os.environ.get("CONTROL_CENTER_API_PORT", DEFAULT_PORT)),
        help=f"порт прослушивания (по умолчанию: {DEFAULT_PORT})",
    )
    parser.add_argument(
        "--manifest",
        default=os.environ.get("CONTROL_CENTER_DEPLOYMENT_MANIFEST"),
        help="путь к deployment manifest",
    )
    parser.add_argument(
        "--allow-non-loopback",
        action="store_true",
        help="явно разрешить привязку вне loopback",
    )
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if args.host not in {"127.0.0.1", "localhost"} and not args.allow_non_loopback:
        raise SystemExit("привязка вне loopback запрещена без --allow-non-loopback")
    if not 1 <= args.port <= 65535:
        raise SystemExit("порт должен находиться в диапазоне 1..65535")

    server = ThreadingHTTPServer((args.host, args.port), make_handler(args.manifest))
    server.daemon_threads = True
    try:
        server.serve_forever(poll_interval=0.25)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
