"""Примитивы безопасности для будущего session layer Control Center.

Модуль намеренно пока не открывает HTTP endpoint входа. Он предоставляет
ограниченные примитивы, которые можно проверить до появления доступного auth flow.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import re
import secrets

SCRYPT_N = 1 << 14
SCRYPT_R = 8
SCRYPT_P = 1
SCRYPT_DKLEN = 32
PASSWORD_MIN_LENGTH = 12
PASSWORD_MAX_LENGTH = 256
SESSION_TOKEN_RE = re.compile(r"^[A-Za-z0-9_-]{40,256}$")


class PasswordPolicyError(ValueError):
    pass


def validate_password(password: str) -> None:
    if not isinstance(password, str):
        raise PasswordPolicyError("password must be a string")
    if not PASSWORD_MIN_LENGTH <= len(password) <= PASSWORD_MAX_LENGTH:
        raise PasswordPolicyError(
            f"password length must be {PASSWORD_MIN_LENGTH}..{PASSWORD_MAX_LENGTH} characters"
        )
    if "\x00" in password:
        raise PasswordPolicyError("password must not contain NUL")


def _b64encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _b64decode(value: str) -> bytes:
    padding = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode(value + padding)


def hash_password(password: str) -> str:
    validate_password(password)
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(
        password.encode("utf-8"),
        salt=salt,
        n=SCRYPT_N,
        r=SCRYPT_R,
        p=SCRYPT_P,
        dklen=SCRYPT_DKLEN,
    )
    return (
        f"scrypt${SCRYPT_N}${SCRYPT_R}${SCRYPT_P}$"
        f"{_b64encode(salt)}${_b64encode(digest)}"
    )


def verify_password(password: str, encoded: str) -> bool:
    if not isinstance(password, str) or not isinstance(encoded, str):
        return False
    try:
        algorithm, n_raw, r_raw, p_raw, salt_raw, digest_raw = encoded.split("$", 5)
        if algorithm != "scrypt":
            return False
        n, r, p = int(n_raw), int(r_raw), int(p_raw)
        if (n, r, p) != (SCRYPT_N, SCRYPT_R, SCRYPT_P):
            return False
        salt = _b64decode(salt_raw)
        expected = _b64decode(digest_raw)
        if len(salt) != 16 or len(expected) != SCRYPT_DKLEN:
            return False
        candidate = hashlib.scrypt(
            password.encode("utf-8"),
            salt=salt,
            n=n,
            r=r,
            p=p,
            dklen=len(expected),
        )
    except (ValueError, TypeError):
        return False
    return hmac.compare_digest(candidate, expected)


def issue_session_token() -> str:
    token = secrets.token_urlsafe(32)
    if not SESSION_TOKEN_RE.fullmatch(token):
        raise RuntimeError("generated session token failed validation")
    return token


def hash_session_token(token: str) -> str:
    if not isinstance(token, str) or not SESSION_TOKEN_RE.fullmatch(token):
        raise ValueError("invalid session token")
    return hashlib.sha256(token.encode("ascii")).hexdigest()


def secure_session_cookie(token: str, max_age_seconds: int) -> str:
    if not isinstance(token, str) or not SESSION_TOKEN_RE.fullmatch(token):
        raise ValueError("invalid session token")
    if not 60 <= max_age_seconds <= 2_592_000:
        raise ValueError("session max age is out of range")
    return (
        f"__Host-cc_session={token}; Path=/; Max-Age={max_age_seconds}; "
        "Secure; HttpOnly; SameSite=Strict"
    )
