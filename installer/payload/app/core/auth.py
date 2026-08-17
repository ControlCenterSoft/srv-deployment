from __future__ import annotations

import base64
import fcntl
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
LOGIN_GUARD_FILE = Path("/var/lib/srv-control/login-guard.json")
COOKIE_NAME = "srvcc_session"
SESSION_TTL = 8 * 60 * 60
LOGIN_WINDOW = 5 * 60
LOGIN_FAILURE_LIMIT = 5
LOGIN_LOCKOUT = 15 * 60


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


def _session_generation(auth: dict | None = None) -> int:
    auth = auth if auth is not None else _load_auth()
    try:
        return max(1, int(auth.get("session_generation", 1)))
    except Exception:
        return 1


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
        "session_generation": _session_generation(auth),
    }


def create_session(username: str, must_change: bool) -> tuple[str, str]:
    auth = _load_auth()
    now = int(time.time())
    csrf = secrets.token_urlsafe(24)
    payload = {
        "u": username,
        "iat": now,
        "exp": now + SESSION_TTL,
        "csrf": csrf,
        "must_change": bool(must_change),
        "gen": _session_generation(auth),
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

    auth = _load_auth()
    if payload.get("u") != auth.get("username"):
        return None

    try:
        token_generation = int(payload.get("gen", 0))
    except Exception:
        return None
    if token_generation != _session_generation(auth):
        return None

    return payload


def require_session(request: Request, *, allow_password_change: bool = False) -> dict:
    session = parse_session(request)
    if session is None:
        raise HTTPException(status_code=401, detail="authentication required")

    if session.get("must_change") and not allow_password_change:
        raise HTTPException(
            status_code=403,
            detail="administrator password must be changed",
        )

    return session


def require_csrf(request: Request, session: dict) -> None:
    supplied = request.headers.get("X-CSRF-Token", "")
    expected = str(session.get("csrf", ""))
    if not supplied or not hmac.compare_digest(supplied, expected):
        raise HTTPException(status_code=403, detail="CSRF validation failed")


def change_password(username: str, current_password: str, new_password: str) -> None:
    if len(new_password) < 12:
        raise ValueError("new password must contain at least 12 characters")
    if new_password == current_password:
        raise ValueError("new password must be different from current password")
    if username.lower() in new_password.lower():
        raise ValueError("new password must not contain the administrator login")

    account = authenticate(username, current_password)
    if account is None:
        raise ValueError("current password is invalid")

    current = _load_auth()
    salt = os.urandom(16)
    iterations = 310000
    payload = {
        "schema_version": 2,
        "username": username,
        "salt": salt.hex(),
        "password_hash": _password_hash(new_password, salt, iterations).hex(),
        "iterations": iterations,
        "must_change": False,
        "session_generation": _session_generation(current) + 1,
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


def _guard_key(username: str, client_ip: str | None) -> str:
    raw = f"{username.strip().lower()}|{client_ip or 'unknown'}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _guard_update(username: str, client_ip: str | None, *, success: bool | None) -> int:
    key = _guard_key(username, client_ip)
    now = int(time.time())
    LOGIN_GUARD_FILE.parent.mkdir(parents=True, exist_ok=True)

    with LOGIN_GUARD_FILE.open("a+", encoding="utf-8") as handle:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        handle.seek(0)
        try:
            state = json.load(handle)
            if not isinstance(state, dict):
                state = {}
        except Exception:
            state = {}

        entries = state.get("entries")
        if not isinstance(entries, dict):
            entries = {}

        item = entries.get(key)
        if not isinstance(item, dict):
            item = {"failures": [], "locked_until": 0}

        failures = [
            int(value)
            for value in item.get("failures", [])
            if isinstance(value, (int, float)) and int(value) >= now - LOGIN_WINDOW
        ]
        locked_until = int(item.get("locked_until", 0) or 0)

        if success is True:
            entries.pop(key, None)
            locked_until = 0
        else:
            if success is False and locked_until <= now:
                failures.append(now)
                if len(failures) >= LOGIN_FAILURE_LIMIT:
                    locked_until = now + LOGIN_LOCKOUT
                    failures = []
            entries[key] = {
                "failures": failures[-LOGIN_FAILURE_LIMIT:],
                "locked_until": locked_until,
                "updated_at": now,
            }

        if len(entries) > 256:
            ordered = sorted(
                entries.items(),
                key=lambda pair: int(pair[1].get("updated_at", 0) or 0),
                reverse=True,
            )
            entries = dict(ordered[:256])

        state = {"schema_version": 1, "entries": entries}
        handle.seek(0)
        handle.truncate()
        json.dump(state, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
        handle.flush()
        os.fchmod(handle.fileno(), 0o640)
        fcntl.flock(handle.fileno(), fcntl.LOCK_UN)

    return max(0, locked_until - now)


def login_retry_after(username: str, client_ip: str | None) -> int:
    return _guard_update(username, client_ip, success=None)


def record_login_result(username: str, client_ip: str | None, success: bool) -> int:
    return _guard_update(username, client_ip, success=success)
