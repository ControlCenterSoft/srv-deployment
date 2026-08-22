#!/usr/bin/env python3
"""Control Center ops agent 1.1.10 using a local SO_PEERCRED Unix broker."""
from __future__ import annotations

import datetime as dt
import json
import os
import pathlib
import socket
import struct
import sys
from typing import Any

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import ccops_agent_v2 as base  # noqa: E402

AGENT_VERSION = "1.1.10"
SOCKET_PATH = "/run/control-center-ops/broker.sock"
MAX_RESPONSE_BYTES = 128 * 1024
PLATFORM_PREPARE_ACTION = "platform.prepare-v2"
PRIVILEGED_WORKER_SERVICE = "control-center-privileged-worker.service"
REJECTED_ID_MARKER = "last-rejected-command-id"
# platform.prepare-v2 can legitimately spend up to 90 seconds in its bounded
# start/status/failure-diagnostics sequence. Keep the Unix transport deadline
# above that action budget but below the 120 second systemd agent deadline.
BROKER_IO_TIMEOUT_SECONDS = 105.0

# Preserve v2 call targets before monkey-patching the module. Calling
# base.registration_payload() after the assignment below would recurse back
# into this wrapper indefinitely.
_base_registration_payload = base.registration_payload
_base_validate_remote_command = base.validate_remote_command
_base_publish_report = base.publish_report

base.AGENT_VERSION = AGENT_VERSION
base.DEFAULT_BROKER = SOCKET_PATH
base.ALLOWED_ACTIONS.add(PLATFORM_PREPARE_ACTION)
# The package-v2 worker is security-sensitive but must be observable during
# staging/acceptance. Keep this read-only: it is intentionally not added to the
# restart allowlist.
base.OBSERVABLE_SERVICES.add(PRIVILEGED_WORKER_SERVICE)
# The v2 main() only requires REQUEST_DIR to exist. The socket transport does
# not use request files, so bind that compatibility check to the private state dir.
base.REQUEST_DIR = base.OPS_STATE_DIR


def _peer_uid(conn: socket.socket) -> int:
    raw = conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i"))
    _, uid, _ = struct.unpack("3i", raw)
    return uid


def broker_request(command: dict[str, Any], broker: str) -> dict[str, Any]:
    socket_path = broker or SOCKET_PATH
    payload = {"schema": 1, "id": command["id"], "action": command["action"], "args": command["args"]}
    raw = (json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n").encode()
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
            conn.settimeout(BROKER_IO_TIMEOUT_SECONDS)
            conn.connect(socket_path)
            if _peer_uid(conn) != 0:
                return {"transport_exit_code": 77, "broker": {"ok": False, "error": "broker peer is not root"}, "stderr": ""}
            conn.sendall(raw)
            conn.shutdown(socket.SHUT_WR)
            response = bytearray()
            while len(response) <= MAX_RESPONSE_BYTES:
                chunk = conn.recv(min(4096, MAX_RESPONSE_BYTES + 1 - len(response)))
                if not chunk:
                    break
                response.extend(chunk)
                if b"\n" in chunk:
                    break
        if len(response) > MAX_RESPONSE_BYTES:
            return {"transport_exit_code": 70, "broker": {"ok": False, "error": "broker response too large"}, "stderr": ""}
        if not response.endswith(b"\n") or response[:-1].find(b"\n") != -1:
            return {"transport_exit_code": 70, "broker": {"ok": False, "error": "invalid broker frame"}, "stderr": ""}
        try:
            broker_payload = json.loads(response[:-1].decode("utf-8", errors="strict"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            broker_payload = {"ok": False, "error": "broker returned invalid JSON"}
        ok = isinstance(broker_payload, dict) and broker_payload.get("ok") is True
        return {"transport_exit_code": 0 if ok else 1, "broker": broker_payload, "stderr": ""}
    except (FileNotFoundError, ConnectionRefusedError, socket.timeout, OSError) as exc:
        return {"transport_exit_code": 69, "broker": {"ok": False, "error": "broker transport unavailable"},
                "stderr": base.redact(type(exc).__name__)}


def validate_remote_command(command: Any) -> tuple[bool, str]:
    if not isinstance(command, dict) or command.get("action") != PLATFORM_PREPARE_ACTION:
        return _base_validate_remote_command(command)
    if set(command) != {"schema", "id", "action", "args", "expires_at"}:
        return False, "invalid command shape"
    if command.get("schema") != 1 or not isinstance(command.get("id"), str) or not base.ID_RE.fullmatch(command["id"]):
        return False, "invalid schema or id"
    if command.get("args") != {}:
        return False, "platform preparation does not accept arguments"
    try:
        expiry = base.parse_expiry(command["expires_at"])
    except (KeyError, TypeError, ValueError):
        return False, "invalid expiry"
    now = base.utc_now()
    if now >= expiry or expiry - now > dt.timedelta(minutes=30):
        return False, "expiry rejected"
    return True, "ok"


def publish_report(client: Any, repo: str, branch: str, server_id: str, report: dict[str, Any]) -> None:
    """Publish each rejected command ID once while preserving normal reports.

    The v2 loop reports validation failures before its executed-command replay
    marker is consulted. A stale expired command could therefore create a new
    Git commit on every timer tick. Rejected IDs are immutable command
    identities, so remember the last successfully published rejected ID in the
    existing private state directory and suppress only consecutive replays.
    """
    if report.get("rejected") is not True:
        _base_publish_report(client, repo, branch, server_id, report)
        return

    report_id = report.get("id")
    if not isinstance(report_id, str) or not base.ID_RE.fullmatch(report_id):
        _base_publish_report(client, repo, branch, server_id, report)
        return

    marker = base.OPS_STATE_DIR / REJECTED_ID_MARKER
    try:
        if marker.exists() and marker.read_text(encoding="utf-8").strip() == report_id:
            return
    except OSError:
        # Fail open for evidence: a local marker read problem must never hide a
        # newly rejected remote command.
        pass

    _base_publish_report(client, repo, branch, server_id, report)
    marker.write_text(report_id + "\n", encoding="utf-8")
    os.chmod(marker, 0o600)


def registration_payload(server_id: str) -> dict[str, Any]:
    payload = _base_registration_payload(server_id)
    payload["agent_version"] = AGENT_VERSION
    payload["privilege_boundary"] = "unix-so-peercred-root-broker"
    payload["broker_transport"] = "unix"
    payload["sudo_required"] = False
    payload["capabilities"] = sorted(base.ALLOWED_ACTIONS)
    return payload


base.broker_request = broker_request
base.validate_remote_command = validate_remote_command
base.publish_report = publish_report
base.registration_payload = registration_payload


def main() -> int:
    return base.main()


if __name__ == "__main__":
    raise SystemExit(main())
