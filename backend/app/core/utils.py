"""Small shared utilities."""

from __future__ import annotations

import hashlib
import re
import unicodedata
import uuid
from datetime import UTC, datetime


def utcnow() -> datetime:
    """Naive UTC timestamp (SQLite friendly, serialized with a trailing Z)."""
    return datetime.now(UTC).replace(tzinfo=None)


def iso(dt: datetime | None) -> str | None:
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=UTC)
    return dt.astimezone(UTC).isoformat().replace("+00:00", "Z")


def new_id() -> str:
    return str(uuid.uuid4())


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def sha256_file(path, chunk_size: int = 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        while chunk := handle.read(chunk_size):
            digest.update(chunk)
    return digest.hexdigest()


_WS_RE = re.compile(r"[ \t\u00a0\u3000]+")


def normalize_text(value: str) -> str:
    """Normalize for indexing/splitting only; never overwrites original text."""
    value = unicodedata.normalize("NFC", value)
    value = value.replace("\r\n", "\n").replace("\r", "\n")
    value = _WS_RE.sub(" ", value)
    return value.strip()


def normalize_punctuation(value: str) -> str:
    """Map full-width ASCII punctuation to ASCII for structural analysis."""
    table = str.maketrans({
        "，": ",", "。": ".", "；": ";", "：": ":", "？": "?", "！": "!",
        "（": "(", "）": ")", "【": "[", "】": "]", "《": "<", "》": ">",
        "、": ",", "“": '"', "”": '"', "‘": "'", "’": "'",
    })
    return value.translate(table)


def clamp(value: int, low: int, high: int) -> int:
    return max(low, min(high, value))


def safe_filename(name: str) -> str:
    name = name.replace("\\", "/").split("/")[-1].strip()
    name = re.sub(r'[<>:"|?*\x00-\x1f]', "_", name)
    return name[:180] or "book"
