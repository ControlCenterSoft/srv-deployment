from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import secrets
import time
from pathlib import Path

from fastapi import HTTPException, Request


AUTH_FILE = Path("/var/lib/srv-control/auth.json")
SESSION_KEY_FILE = Path("/var/lib/srv-control/session.key")
BOOTSTRAP_FILE = Path("/var/lib/srv-control/admin-bootstrap.txt")
COOKIE_NAME = "srvcc_session"
SESSION_TTL = 8 * 60 * 60


def _b64encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def _b64decode(value: str) -> bytes:
    padding = "=" * ((4 - len(value) % 4) % 4)
    return base64.urlsafe_b64decode((value + padding).encode("ascii"))


def _load_auth() -> dict:
    try:
        payload = json.loads(AUTH_FILE.read_text(encoding="utf-8"))
        if isinstance(payload, dict):
            return payload
    except Exception:
        pass
    return {}


def _session_key() -> bytes:
    raw = SESSION_KEY_FILE.read_text(encoding="ascii").strip()
    return bytes.fromhex(raw)


def _password_hash(password: str, salt: bytes, iterations: int) -> bytes:
    return hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt,
        iterations,
    )


def authenticate(username: str, password: str) -> dict | None:
    auth = _load_auth()
    if username != auth.get("username"):
        return None

    try:
        salt = bytes.fromhex(str(auth["salt"]))
        expected = bytes.fromhex(str(auth["password_hash"]))
        iterations = int(auth.get("iterations", 310000))
    except Exception:
        return None

    actual = _password_hash(password, salt, iterations)
    if not hmac.compare_digest(actual, expected):
        return None

    return {
        "username": username,
        "must_change": bool(auth.get("must_change", False)),
    }


def create_session(username: str, must_change: bool) -> tuple[str, str]:
    now = int(time.time())
    csrf = secrets.token_urlsafe(24)
    payload = {
        "u": username,
        "iat": now,
        "exp": now + SESSION_TTL,
        "csrf": csrf,
        "must_change": bool(must_change),
    }
    body = _b64encode(
        json.dumps(
            payload,
            ensure_ascii=False,
            separators=(",", ":"),
        ).encode("utf-8")
    )
    signature = _b64encode(
        hmac.new(
            _session_key(),
            body.encode("ascii"),
            hashlib.sha256,
        ).digest()
    )
    return f"{body}.{signature}", csrf


def parse_session(request: Request) -> dict | None:
    token = request.cookies.get(COOKIE_NAME)
    if not token or "." not in token:
        return None

    body, signature = token.rsplit(".", 1)
    expected = _b64encode(
        hmac.new(
            _session_key(),
            body.encode("ascii"),
            hashlib.sha256,
        ).digest()
    )
    if not hmac.compare_digest(signature, expected):
        return None

    try:
        payload = json.loads(_b64decode(body))
    except Exception:
        return None

    if int(payload.get("exp", 0)) < int(time.time()):
        return None

    if not payload.get("u") or not payload.get("csrf"):
        return None

    return payload


def require_session(request: Request, *, allow_password_change: bool = False) -> dict:
    session = parse_session(request)
    if session is None:
        raise HTTPException(status_code=401, detail="authentication required")

    if session.get("must_change") and not allow_password_change:
        raise HTTPException(status_code=403, detail="administrator password must be changed")

    return session


def require_csrf(request: Request, session: dict) -> None:
    supplied = request.headers.get("X-CSRF-Token", "")
    expected = str(session.get("csrf", ""))
    if not supplied or not hmac.compare_digest(supplied, expected):
        raise HTTPException(status_code=403, detail="CSRF validation failed")


def change_password(username: str, current_password: str, new_password: str) -> None:
    if len(new_password) < 12:
        raise ValueError("new password must contain at least 12 characters")

    account = authenticate(username, current_password)
    if account is None:
        raise ValueError("current password is invalid")

    salt = os.urandom(16)
    iterations = 310000
    payload = {
        "schema_version": 1,
        "username": username,
        "salt": salt.hex(),
        "password_hash": _password_hash(new_password, salt, iterations).hex(),
        "iterations": iterations,
        "must_change": False,
    }

    tmp = AUTH_FILE.with_suffix(".json.tmp")
    tmp.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    os.chmod(tmp, 0o640)
    os.replace(tmp, AUTH_FILE)

    try:
        BOOTSTRAP_FILE.unlink()
    except FileNotFoundError:
        pass
