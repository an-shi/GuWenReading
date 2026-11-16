"""Local backup creation and listing.

Backups are complete ZIP archives of the managed data directory: the SQLite
database (taken with SQLite's online backup API), original book files, extracted
text and covers. Restore is intentionally a stopped-service operation; see
scripts/restore_backup.py.
"""

from __future__ import annotations

import json
import sqlite3
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import unquote

from sqlalchemy.engine import make_url

from app.core.config import Settings
from app.core.errors import AppError, ErrorCode


def database_path(settings: Settings) -> Path:
    if not settings.database_url or "sqlite" not in settings.database_url:
        raise AppError(
            ErrorCode.VALIDATION_ERROR,
            "Backup is only supported for the embedded SQLite database",
            status_code=409,
        )
    url = make_url(settings.database_url)
    if not url.database:
        raise AppError(ErrorCode.VALIDATION_ERROR, "SQLite database path is unknown", status_code=500)
    return Path(unquote(url.database)).resolve()


def create_backup(settings: Settings) -> dict:
    settings.backups_dir.mkdir(parents=True, exist_ok=True)
    source_db = database_path(settings)
    if not source_db.exists():
        raise AppError(ErrorCode.NOT_FOUND, "Database file does not exist", status_code=404)

    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    filename = f"古文阅读器备份-{stamp}.zip"
    target = settings.backups_dir / filename
    snapshot = settings.tmp_dir / f"db-snapshot-{stamp}.sqlite"
    snapshot.parent.mkdir(parents=True, exist_ok=True)

    source = sqlite3.connect(str(source_db))
    destination = sqlite3.connect(str(snapshot))
    try:
        source.backup(destination)
    finally:
        destination.close()
        source.close()

    try:
        with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            archive.write(snapshot, "database/guwen.db")
            if settings.books_dir.exists():
                for path in settings.books_dir.rglob("*"):
                    if path.is_file():
                        archive.write(path, path.relative_to(settings.data_dir).as_posix())
            if settings.covers_dir.exists():
                for path in settings.covers_dir.rglob("*"):
                    if path.is_file():
                        archive.write(path, path.relative_to(settings.data_dir).as_posix())
            archive.writestr(
                "backup.json",
                json.dumps({
                    "app": settings.app_name,
                    "version": settings.version,
                    "created_at": datetime.now(timezone.utc).isoformat(),
                    "format": "guwenreading.backup.v1",
                }, ensure_ascii=False, indent=2),
            )
    finally:
        snapshot.unlink(missing_ok=True)

    return {
        "filename": filename,
        "size": target.stat().st_size,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "download_url": f"/api/v1/system/backups/{filename}",
    }


def list_backups(settings: Settings) -> list[dict]:
    if not settings.backups_dir.exists():
        return []
    items = []
    for path in sorted(settings.backups_dir.glob("古文阅读器备份-*.zip"), reverse=True):
        stat = path.stat()
        items.append({
            "filename": path.name,
            "size": stat.st_size,
            "created_at": datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).isoformat(),
            "download_url": f"/api/v1/system/backups/{path.name}",
        })
    return items


def resolve_backup(settings: Settings, filename: str) -> Path:
    if "/" in filename or "\\" in filename or ".." in filename:
        raise AppError(ErrorCode.NOT_FOUND, "Backup not found", status_code=404)
    path = (settings.backups_dir / filename).resolve()
    if path.parent != settings.backups_dir.resolve() or not path.exists():
        raise AppError(ErrorCode.NOT_FOUND, "Backup not found", status_code=404)
    return path
