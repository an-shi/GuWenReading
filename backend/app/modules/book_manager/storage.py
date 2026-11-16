"""Managed book storage helpers."""

from __future__ import annotations

import mimetypes
from pathlib import Path

from app.core.config import Settings

IMAGE_SIGNATURES = {
    b"\xff\xd8\xff": ".jpg",
    b"\x89PNG\r\n\x1a\n": ".png",
    b"GIF87a": ".gif",
    b"GIF89a": ".gif",
    b"RIFF": ".webp",
}


def resolve_data_path(settings: Settings, relative_path: str | None) -> Path | None:
    if not relative_path:
        return None
    candidate = (settings.data_dir / relative_path).resolve()
    # Never allow a stored path to escape the managed data directory.
    if settings.data_dir not in candidate.parents and candidate != settings.data_dir:
        return None
    return candidate


def image_extension(data: bytes) -> str | None:
    for signature, extension in IMAGE_SIGNATURES.items():
        if data.startswith(signature):
            return extension
    return None


def guess_media_type(path: Path) -> str:
    return mimetypes.guess_type(path.name)[0] or "application/octet-stream"


def managed_relative(settings: Settings, path: Path) -> str:
    return path.resolve().relative_to(settings.data_dir).as_posix()
