#!/usr/bin/env python3
"""Control Center Fleet Agent 1.1.0.

Unprivileged node-side client for one-time enrollment and periodic inventory
heartbeat. It deliberately has no shell/command execution capability.
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import platform
import re
import socket
import stat
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

AGENT_VERSION = "1.1.0"
DEFAULT_CONFIG = pathlib.Path("/etc/control-center-fleet-agent/agent.conf")
DEFAULT_CREDENTIAL = pathlib.Path("/var/lib/control-center-fleet-agent/agent-credential")
NODE_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$")
LOOPBACK_HOSTS = {"127.0.0.1", "::1", "localhost"}
MAX_ERROR_BYTES = 64 * 1024


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: ANN001
        return None


OPENER = urllib.request.build_opener(NoRedirect())


def fail(message: str, code: int = 1) -> "NoReturn":
    print(f"FLEET_AGENT_ERROR {message}", file=sys.stderr)
    raise SystemExit(code)


def load_config(path: pathlib.Path) -> dict[str, str]:
    data: dict[str, str] = {}
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        fail(f"config_unavailable={type(exc).__name__}")
    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            fail("invalid_config_line")
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if key not in {"CONTROL_CENTER_URL", "FLEET_NODE_ID"}:
            fail("unknown_config_key")
        if not value or any(ch in value for ch in "\r\n\t"):
            fail("invalid_config_value")
        data[key] = value
    for key in ("CONTROL_CENTER_URL", "FLEET_NODE_ID"):
        if not data.get(key):
            fail(f"missing_config={key}")
    return data


def normalize_base_url(value: str) -> str:
    try:
        parsed = urllib.parse.urlsplit(value.strip())
    except ValueError:
        fail("invalid_control_center_url")
    if parsed.username is not None or parsed.password is not None:
        fail("userinfo_in_control_center_url")
    if parsed.query or parsed.fragment or parsed.path not in {"", "/"}:
        fail("control_center_url_must_be_origin")
    host = (parsed.hostname or "").lower()
    if parsed.scheme == "https":
        pass
    elif parsed.scheme == "http" and host in LOOPBACK_HOSTS:
        pass
    else:
        fail("https_required")
    if not host:
        fail("missing_control_center_host")
    try:
        port = parsed.port
    except ValueError:
        fail("invalid_control_center_port")
    netloc = parsed.hostname or ""
    if ":" in netloc and not netloc.startswith("["):
        netloc = f"[{netloc}]"
    if port is not None:
        netloc = f"{netloc}:{port}"
    return f"{parsed.scheme}://{netloc}"


def validate_node_id(value: str) -> str:
    value = value.strip()
    if not NODE_ID_RE.fullmatch(value):
        fail("invalid_node_id")
    return value.lower()


def bounded(value: Any, maximum: int) -> str:
    text = str(value or "").strip().replace("\r", " ").replace("\n", " ").replace("\t", " ")
    return text[:maximum]


def architecture() -> str:
    raw = platform.machine().lower()
    return {"x86_64": "amd64", "amd64": "amd64", "aarch64": "arm64", "arm64": "arm64"}.get(raw, bounded(raw, 64))


def os_inventory() -> tuple[str, str]:
    name = platform.system() or "Linux"
    version = platform.release()
    try:
        info = platform.freedesktop_os_release()
        name = info.get("NAME") or info.get("ID") or name
        version = info.get("VERSION_ID") or info.get("VERSION") or version
    except (OSError, AttributeError):
        pass
    return bounded(name, 128), bounded(version, 128)


def safe_error_code(raw: bytes) -> str:
    if not raw:
        return "http_error"
    try:
        payload = json.loads(raw.decode("utf-8", errors="strict"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return "http_error"
    value = payload.get("error") if isinstance(payload, dict) else None
    if isinstance(value, dict):
        value = value.get("code")
    if isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9._-]{1,80}", value):
        return value
    return "http_error"


def post_json(base_url: str, path: str, payload: dict[str, Any], bearer: str = "") -> dict[str, Any]:
    body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    headers = {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "User-Agent": f"control-center-fleet-agent/{AGENT_VERSION}",
    }
    if bearer:
        headers["Authorization"] = f"Bearer {bearer}"
    request = urllib.request.Request(base_url + path, data=body, method="POST", headers=headers)
    try:
        with OPENER.open(request, timeout=20) as response:
            raw = response.read(MAX_ERROR_BYTES + 1)
            if len(raw) > MAX_ERROR_BYTES:
                fail("response_too_large")
            result = json.loads(raw.decode("utf-8")) if raw else {}
    except urllib.error.HTTPError as exc:
        raw = exc.read(MAX_ERROR_BYTES)
        fail(f"http_status={exc.code} code={safe_error_code(raw)}")
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        fail(f"transport={type(exc).__name__}")
    except (UnicodeDecodeError, json.JSONDecodeError):
        fail("invalid_json_response")
    if not isinstance(result, dict):
        fail("invalid_response_shape")
    return result


def read_secret(path: pathlib.Path) -> str:
    try:
        info = path.lstat()
    except OSError as exc:
        fail(f"credential_unavailable={type(exc).__name__}")
    if not stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode):
        fail("credential_not_regular_file")
    if info.st_mode & 0o077:
        fail("credential_permissions_too_open")
    try:
        value = path.read_text(encoding="utf-8").strip()
    except OSError as exc:
        fail(f"credential_read_failed={type(exc).__name__}")
    if not value or len(value) > 512 or any(ch.isspace() for ch in value):
        fail("invalid_credential")
    return value


def write_secret(path: pathlib.Path, value: str) -> None:
    if not value or len(value) > 512 or any(ch.isspace() for ch in value):
        fail("invalid_credential_response")
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=".agent-credential.", dir=str(path.parent), text=True)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(value + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_name, path)
        os.chmod(path, 0o600)
    except Exception:
        try:
            os.close(fd)
        except OSError:
            pass
        try:
            os.unlink(temp_name)
        except OSError:
            pass
        raise


def enroll(base_url: str, node_id: str, token_file: pathlib.Path, credential_file: pathlib.Path) -> None:
    token = read_secret(token_file)
    response = post_json(base_url, "/api/v1/fleet/enroll", {
        "node_id": node_id,
        "token": token,
        "agent_version": AGENT_VERSION,
    })
    credential = response.get("agent_credential")
    if not isinstance(credential, str):
        fail("missing_agent_credential")
    write_secret(credential_file, credential)
    print(f"FLEET_AGENT_ENROLL=PASSED node_id={node_id} agent_version={AGENT_VERSION}")


def heartbeat(base_url: str, node_id: str, credential_file: pathlib.Path) -> None:
    credential = read_secret(credential_file)
    os_name, os_version = os_inventory()
    response = post_json(base_url, "/api/v1/fleet/heartbeat", {
        "node_id": node_id,
        "agent_version": AGENT_VERSION,
        "hostname": bounded(socket.gethostname(), 255),
        "os_name": os_name,
        "os_version": os_version,
        "architecture": architecture(),
    }, bearer=credential)
    if response.get("health") != "healthy":
        fail("heartbeat_not_accepted")
    print(f"FLEET_AGENT_HEARTBEAT=PASSED node_id={node_id} agent_version={AGENT_VERSION}")


def self_test() -> None:
    if normalize_base_url("https://control-center.example") != "https://control-center.example":
        fail("self_test_https")
    if normalize_base_url("http://127.0.0.1:8876") != "http://127.0.0.1:8876":
        fail("self_test_loopback")
    if validate_node_id("Srv-01") != "srv-01":
        fail("self_test_node")
    os_name, _ = os_inventory()
    if not os_name or not architecture():
        fail("self_test_inventory")
    print(f"FLEET_AGENT_SELF_TEST=PASSED agent_version={AGENT_VERSION}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=str(DEFAULT_CONFIG))
    parser.add_argument("--credential-file", default=str(DEFAULT_CREDENTIAL))
    parser.add_argument("--enroll-token-file")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    cfg = load_config(pathlib.Path(args.config))
    base_url = normalize_base_url(cfg["CONTROL_CENTER_URL"])
    node_id = validate_node_id(cfg["FLEET_NODE_ID"])
    credential_file = pathlib.Path(args.credential_file)
    if args.enroll_token_file:
        enroll(base_url, node_id, pathlib.Path(args.enroll_token_file), credential_file)
    else:
        heartbeat(base_url, node_id, credential_file)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
