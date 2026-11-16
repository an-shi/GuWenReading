"""Secret storage and authentication primitives.

API keys are encrypted at rest. Windows uses DPAPI; server deployments use a
Fernet key derived from GUWEN_SECRET_KEY; other platforms use a protected local
key file. Logging never receives plaintext keys.
"""

from __future__ import annotations

import base64
import ctypes
import hashlib
import hmac
import os
import secrets
import sys
from ctypes import wintypes
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

import jwt
from cryptography.fernet import Fernet, InvalidToken

from app.core.config import Settings
from app.core.errors import AppError, ErrorCode

PBKDF2_ITERATIONS = 600_000


def mask_secret(value: str | None) -> str | None:
    if not value:
        return None
    if len(value) <= 8:
        return "****"
    return f"****{value[-4:]}"


# --------------------------------------------------------------------------- DPAPI
if sys.platform == "win32":
    class _DataBlob(ctypes.Structure):
        _fields_ = [
            ("cbData", wintypes.DWORD),
            ("pbData", ctypes.POINTER(ctypes.c_char)),
        ]

    _crypt32 = ctypes.windll.crypt32
    _crypt32.CryptProtectData.argtypes = [
        ctypes.POINTER(_DataBlob),
        wintypes.LPCWSTR,
        ctypes.POINTER(_DataBlob),
        ctypes.c_void_p,
        ctypes.c_void_p,
        wintypes.DWORD,
        ctypes.POINTER(_DataBlob),
    ]
    _crypt32.CryptProtectData.restype = wintypes.BOOL
    _crypt32.CryptUnprotectData.argtypes = [
        ctypes.POINTER(_DataBlob),
        ctypes.POINTER(wintypes.LPWSTR),
        ctypes.POINTER(_DataBlob),
        ctypes.c_void_p,
        ctypes.c_void_p,
        wintypes.DWORD,
        ctypes.POINTER(_DataBlob),
    ]
    _crypt32.CryptUnprotectData.restype = wintypes.BOOL
    _kernel32 = ctypes.windll.kernel32
    _kernel32.LocalFree.argtypes = [ctypes.c_void_p]


def _dpapi_protect(data: bytes) -> bytes:
    if sys.platform != "win32":
        raise RuntimeError("DPAPI is only available on Windows")
    buffer = ctypes.create_string_buffer(data, len(data))
    blob_in = _DataBlob(len(data), ctypes.cast(buffer, ctypes.POINTER(ctypes.c_char)))
    blob_out = _DataBlob()
    if not _crypt32.CryptProtectData(
        ctypes.byref(blob_in), "古文阅读器接口密钥", None, None, None, 0x1, ctypes.byref(blob_out)
    ):
        raise ctypes.WinError()
    try:
        return ctypes.string_at(blob_out.pbData, blob_out.cbData)
    finally:
        _kernel32.LocalFree(blob_out.pbData)


def _dpapi_unprotect(data: bytes) -> bytes:
    if sys.platform != "win32":
        raise RuntimeError("DPAPI is only available on Windows")
    buffer = ctypes.create_string_buffer(data, len(data))
    blob_in = _DataBlob(len(data), ctypes.cast(buffer, ctypes.POINTER(ctypes.c_char)))
    blob_out = _DataBlob()
    description = wintypes.LPWSTR()
    if not _crypt32.CryptUnprotectData(
        ctypes.byref(blob_in), ctypes.byref(description), None, None, None, 0x1,
        ctypes.byref(blob_out),
    ):
        raise ctypes.WinError()
    try:
        return ctypes.string_at(blob_out.pbData, blob_out.cbData)
    finally:
        _kernel32.LocalFree(blob_out.pbData)


# --------------------------------------------------------------------------- vault
class KeyVault:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._fernet: Fernet | None = None
        self._mode = "dpapi" if (sys.platform == "win32" and not settings.secret_key) else "fernet"

    def _load_fernet(self) -> Fernet:
        if self._fernet is not None:
            return self._fernet
        if self.settings.secret_key:
            material = self.settings.secret_key.encode("utf-8")
        else:
            key_file = self.settings.data_dir / "secrets.key"
            key_file.parent.mkdir(parents=True, exist_ok=True)
            if key_file.exists():
                material = key_file.read_bytes()
            else:
                material = Fernet.generate_key()
                key_file.write_bytes(material)
                try:
                    os.chmod(key_file, 0o600)
                except OSError:
                    pass
        digest = hashlib.sha256(material).digest()
        self._fernet = Fernet(base64.urlsafe_b64encode(digest))
        self._mode = "env" if self.settings.secret_key else "fernet"
        return self._fernet

    def encrypt(self, plaintext: str) -> str:
        if not plaintext:
            return ""
        if self._mode == "dpapi" and not self.settings.secret_key:
            blob = _dpapi_protect(plaintext.encode("utf-8"))
            return "dpapi:" + base64.b64encode(blob).decode("ascii")
        token = self._load_fernet().encrypt(plaintext.encode("utf-8"))
        return f"{self._mode}:" + token.decode("ascii")

    def decrypt(self, stored: str | None) -> str:
        if not stored:
            return ""
        try:
            prefix, _, payload = stored.partition(":")
            if prefix == "dpapi":
                return _dpapi_unprotect(base64.b64decode(payload)).decode("utf-8")
            if prefix in {"fernet", "env"}:
                return self._load_fernet().decrypt(payload.encode("ascii")).decode("utf-8")
        except (InvalidToken, ValueError, OSError) as exc:
            raise AppError(
                ErrorCode.AUTH_INVALID,
                "Stored credential could not be decrypted; re-enter the API key",
                status_code=500,
            ) from exc
        except Exception as exc:  # DPAPI failures
            raise AppError(
                ErrorCode.AUTH_INVALID,
                "Stored credential could not be decrypted; re-enter the API key",
                status_code=500,
            ) from exc
        raise AppError(ErrorCode.AUTH_INVALID, "Unknown credential format", status_code=500)


# --------------------------------------------------------------------------- auth
class SecurityManager:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.vault = KeyVault(settings)
        self._auth_key: bytes | None = None

    def _load_auth_key(self) -> bytes:
        if self._auth_key:
            return self._auth_key
        material = self.settings.auth_secret or self.settings.secret_key
        if material:
            # Derive a fixed-length 256-bit key regardless of passphrase length.
            self._auth_key = hashlib.sha256(material.encode("utf-8")).digest()
            return self._auth_key
        key_file: Path = self.settings.data_dir / "auth.key"
        if key_file.exists():
            self._auth_key = key_file.read_bytes()
        else:
            key_file.parent.mkdir(parents=True, exist_ok=True)
            value = secrets.token_bytes(48)
            key_file.write_bytes(value)
            try:
                os.chmod(key_file, 0o600)
            except OSError:
                pass
            self._auth_key = value
        return self._auth_key

    def create_token(self, user_id: str, username: str) -> str:
        now = datetime.now(UTC)
        payload = {
            "sub": user_id,
            "username": username,
            "iat": int(now.timestamp()),
            "exp": int((now + timedelta(hours=self.settings.token_ttl_hours)).timestamp()),
        }
        return jwt.encode(payload, self._load_auth_key(), algorithm="HS256")

    def decode_token(self, token: str) -> dict[str, Any]:
        try:
            return jwt.decode(token, self._load_auth_key(), algorithms=["HS256"])
        except jwt.PyJWTError as exc:
            raise AppError(ErrorCode.AUTH_INVALID, "Invalid or expired token", status_code=401) from exc


def hash_password(password: str) -> str:
    if len(password) < 8:
        raise AppError(ErrorCode.VALIDATION_ERROR, "Password must be at least 8 characters", status_code=422)
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), PBKDF2_ITERATIONS)
    return f"pbkdf2_sha256${PBKDF2_ITERATIONS}${salt}${base64.b64encode(digest).decode()}"


def verify_password(password: str, stored: str) -> bool:
    try:
        algorithm, iterations, salt, digest = stored.split("$", 3)
        if algorithm != "pbkdf2_sha256":
            return False
        expected = base64.b64decode(digest)
        actual = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), int(iterations))
        return hmac.compare_digest(expected, actual)
    except (ValueError, TypeError):
        return False
