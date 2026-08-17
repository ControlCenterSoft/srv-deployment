from __future__ import annotations

import base64
import fcntl
import hashlib
import hmac
import json
import os
import secrets
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path

from fastapi import HTTPException, Request


SESSION_KEY_FILE = Path("/var/lib/srv-control/session.key")
LOGIN_GUARD_FILE = Path("/var/lib/srv-control/login-guard.json")
COOKIE_NAME = "srvcc_session"
SESSION_TTL = 8 * 60 * 60
LOGIN_WINDOW = 5 * 60
LOGIN_FAILURE_LIMIT = 5
LOGIN_LOCKOUT = 15 * 60
PAM_SERVICE = "srv-control"
TRUSTED_SSO_PEERS = {"127.0.0.1", "::1"}
ADMIN_GROUPS = {"root", "sudo", "wheel", "admin"}


@dataclass(frozen=True)
class Identity:
    username: str
    uid: int
    gid: int
    groups: tuple[str, ...]
    auth_source: str
    is_admin: bool

    def as_dict(self) -> dict:
        return {
            "username": self.username,
            "uid": self.uid,
            "gid": self.gid,
            "groups": list(self.groups),
            "auth_source": self.auth_source,
            "is_admin": self.is_admin,
        }


def _b64encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def _b64decode(value: str) -> bytes:
    padding = "=" * ((4 - len(value) % 4) % 4)
    return base64.urlsafe_b64decode((value + padding).encode("ascii"))


def _session_key() -> bytes:
    raw = SESSION_KEY_FILE.read_text(encoding="ascii").strip()
    return bytes.fromhex(raw)


def _run(
    command: list[str],
    *,
    input_text: str | None = None,
    timeout: float = 8.0,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
        env={**os.environ, "LC_ALL": "C.UTF-8"},
    )


def _identity_candidates(username: str) -> tuple[str, ...]:
    username = username.strip()
    if not username or "\x00" in username or "\n" in username or "\r" in username:
        return ()
    candidates = [username]
    if "\\" in username:
        local = username.rsplit("\\", 1)[-1].strip()
        if local and local not in candidates:
            candidates.append(local)
    if "@" in username:
        local = username.split("@", 1)[0].strip()
        if local and local not in candidates:
            candidates.append(local)
    return tuple(candidates)


def _passwd_record(username: str) -> tuple[str, int, int] | None:
    for candidate in _identity_candidates(username):
        try:
            result = _run(["getent", "passwd", candidate])
        except Exception:
            continue
        if result.returncode != 0:
            continue
        line = result.stdout.splitlines()[0] if result.stdout.splitlines() else ""
        parts = line.split(":")
        if len(parts) < 7:
            continue
        try:
            return parts[0], int(parts[2]), int(parts[3])
        except Exception:
            continue
    return None


def _group_names(username: str) -> tuple[str, ...]:
    try:
        result = _run(["id", "-G", username])
    except Exception:
        return ()
    if result.returncode != 0:
        return ()
    names: list[str] = []
    seen: set[str] = set()
    for raw_gid in result.stdout.split():
        if not raw_gid.isdigit():
            continue
        try:
            group = _run(["getent", "group", raw_gid])
        except Exception:
            continue
        if group.returncode != 0 or not group.stdout.strip():
            continue
        name = group.stdout.split(":", 1)[0].strip()
        if name and name not in seen:
            names.append(name)
            seen.add(name)
    return tuple(names)


def _looks_domain_identity(username: str) -> bool:
    if "@" in username or "\\" in username:
        return True
    if not shutil_which("wbinfo"):
        return False
    try:
        result = _run(["wbinfo", "-n", username], timeout=5.0)
        return result.returncode == 0 and bool(result.stdout.strip())
    except Exception:
        return False


def shutil_which(command: str) -> str | None:
    for directory in os.environ.get("PATH", "").split(os.pathsep):
        candidate = Path(directory) / command
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def resolve_identity(
    username: str,
    auth_source: str | None = None,
) -> Identity | None:
    source = auth_source or ("domain" if _looks_domain_identity(username) else "local")
    record = _passwd_record(username)
    if record is None:
        return None
    canonical, uid, gid = record
    groups = _group_names(canonical)
    group_keys = {group.casefold() for group in groups}
    is_admin = uid == 0 or bool(group_keys & ADMIN_GROUPS)
    return Identity(
        username=canonical,
        uid=uid,
        gid=gid,
        groups=groups,
        auth_source=source,
        is_admin=is_admin,
    )


def authenticate_system(username: str, password: str) -> Identity | None:
    username = username.strip()
    if not username or not password or shutil_which("pamtester") is None:
        return None
    source_hint = "domain" if _looks_domain_identity(username) else None
    if resolve_identity(username, source_hint) is None:
        return None
    try:
        result = _run(
            ["pamtester", PAM_SERVICE, username, "authenticate", "acct_mgmt"],
            input_text=password + "\n",
            timeout=12.0,
        )
    except Exception:
        return None
    if result.returncode != 0:
        return None
    return resolve_identity(username, source_hint)


def create_session(identity: Identity) -> tuple[str, str]:
    now = int(time.time())
    csrf = secrets.token_urlsafe(24)
    payload = {
        "u": identity.username,
        "src": identity.auth_source,
        "iat": now,
        "exp": now + SESSION_TTL,
        "csrf": csrf,
        "nonce": secrets.token_urlsafe(12),
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
    identity = resolve_identity(
        str(payload["u"]),
        str(payload.get("src") or "local"),
    )
    if identity is None:
        return None
    payload["identity"] = identity
    return payload


def require_session(request: Request) -> dict:
    session = parse_session(request)
    if session is None:
        raise HTTPException(status_code=401, detail="authentication required")
    return session


def require_csrf(request: Request, session: dict) -> None:
    supplied = request.headers.get("X-CSRF-Token", "")
    expected = str(session.get("csrf", ""))
    if not supplied or not hmac.compare_digest(supplied, expected):
        raise HTTPException(status_code=403, detail="CSRF validation failed")


def sso_identity(request: Request) -> Identity | None:
    peer = request.client.host if request.client else ""
    if peer not in TRUSTED_SSO_PEERS:
        return None
    username = request.headers.get("X-SRVCC-Remote-User", "").strip()
    if not username:
        return None
    return resolve_identity(username, "sso")


def _guard_key(username: str, client_ip: str | None) -> str:
    raw = f"{username.strip().casefold()}|{client_ip or 'unknown'}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _guard_update(
    username: str,
    client_ip: str | None,
    *,
    success: bool | None,
) -> int:
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
        entries = (
            state.get("entries")
            if isinstance(state.get("entries"), dict)
            else {}
        )
        item = (
            entries.get(key)
            if isinstance(entries.get(key), dict)
            else {"failures": [], "locked_until": 0}
        )
        failures = [
            int(value)
            for value in item.get("failures", [])
            if isinstance(value, (int, float))
            and int(value) >= now - LOGIN_WINDOW
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
        handle.seek(0)
        handle.truncate()
        json.dump(
            {"schema_version": 2, "entries": entries},
            handle,
            ensure_ascii=False,
            indent=2,
        )
        handle.write("\n")
        handle.flush()
        os.fchmod(handle.fileno(), 0o640)
        fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
    return max(0, locked_until - now)


def login_retry_after(username: str, client_ip: str | None) -> int:
    return _guard_update(username, client_ip, success=None)


def record_login_result(
    username: str,
    client_ip: str | None,
    success: bool,
) -> int:
    return _guard_update(username, client_ip, success=success)
