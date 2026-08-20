"""Bounded, secret-redacting audit envelope for Control Center."""

from __future__ import annotations

from datetime import datetime, timezone
import re
import uuid
from typing import Any

SENSITIVE_KEY_RE = re.compile(
    r"(?:authorization|cookie|password|passwd|secret|token|api[_-]?key|session)",
    re.IGNORECASE,
)
SAFE_VALUE_MAX = 512
MAX_ITEMS = 50
MAX_DEPTH = 4


def _text(value: Any) -> str:
    text = str(value)
    return text if len(text) <= SAFE_VALUE_MAX else text[:SAFE_VALUE_MAX] + "…"


def sanitize_audit_value(value: Any, depth: int = 0) -> Any:
    if depth >= MAX_DEPTH:
        return "[TRUNCATED]"
    if value is None or isinstance(value, (bool, int, float)):
        return value
    if isinstance(value, str):
        return _text(value)
    if isinstance(value, dict):
        result: dict[str, Any] = {}
        for index, (key, item) in enumerate(value.items()):
            if index >= MAX_ITEMS:
                result["_truncated"] = True
                break
            safe_key = _text(key)
            result[safe_key] = (
                "[REDACTED]"
                if SENSITIVE_KEY_RE.search(safe_key)
                else sanitize_audit_value(item, depth + 1)
            )
        return result
    if isinstance(value, (list, tuple)):
        items = list(value[:MAX_ITEMS])
        result = [sanitize_audit_value(item, depth + 1) for item in items]
        if len(value) > MAX_ITEMS:
            result.append("[TRUNCATED]")
        return result
    return _text(value)


def build_audit_event(
    *,
    correlation_id: str,
    actor_id: str | None,
    role: str | None,
    action: str,
    outcome: str,
    target: str | None = None,
    details: dict[str, Any] | None = None,
) -> dict[str, Any]:
    if outcome not in {"allowed", "denied", "success", "failure"}:
        raise ValueError("invalid audit outcome")
    if not action or len(action) > 128:
        raise ValueError("invalid audit action")
    return {
        "schema": 1,
        "event_id": str(uuid.uuid4()),
        "occurred_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "correlation_id": _text(correlation_id),
        "actor_id": _text(actor_id) if actor_id is not None else None,
        "role": _text(role) if role is not None else None,
        "action": _text(action),
        "outcome": outcome,
        "target": _text(target) if target is not None else None,
        "details": sanitize_audit_value(details or {}),
    }
