"""Health, capabilities and database status."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Request
from fastapi.responses import FileResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_session, get_settings_dep, require_auth
from app.core.config import Settings
from app.core.responses import ok
from app.database.session import check_database
from app.modules.document_parser import SUPPORTED_FORMATS
from app.modules.system.backup import create_backup, list_backups, resolve_backup

router = APIRouter(tags=["system"])


@router.get("/system/health")
async def health(request: Request, session: AsyncSession = Depends(get_session)):
    try:
        database_ok = await check_database(request.app.state.engine)
    except Exception:
        database_ok = False
    return ok({
        "status": "ok" if database_ok else "degraded",
        "database": database_ok,
        "version": request.app.state.settings.version,
    })


@router.get("/system/info")
async def info(
    request: Request,
    settings: Settings = Depends(get_settings_dep),
    session: AsyncSession = Depends(get_session),
):
    from sqlalchemy import func, select
    from app.database.models import AIProvider, AIModel, Book

    books = await session.scalar(
        select(func.count()).select_from(Book).where(Book.deleted_at.is_(None))
    ) or 0
    providers = await session.scalar(
        select(func.count()).select_from(AIProvider).where(AIProvider.enabled.is_(True))
    ) or 0
    models = await session.scalar(
        select(func.count()).select_from(AIModel).where(AIModel.enabled.is_(True))
    ) or 0
    return ok({
        "name": settings.app_name,
        "version": settings.version,
        "mode": settings.mode,
        "auth_required": settings.auth_required,
        "supported_formats": list(SUPPORTED_FORMATS),
        "capabilities": {
            "epub": True, "pdf_text": True, "pdf_ocr": False, "docx": True, "txt": True,
            "fts5": request.app.state.fts_available,
            "sync": settings.sync_enabled or settings.mode == "server",
            "ai": models > 0,
            "backup": "sqlite" in (settings.database_url or ""),
        },
        "counts": {"books": books, "providers": providers, "models": models},
        "data_dir": str(settings.data_dir) if settings.mode == "embedded" else None,
    })


@router.post("/system/backup", status_code=201)
async def create_system_backup(
    settings: Settings = Depends(get_settings_dep),
    _user=Depends(require_auth),
):
    import asyncio

    backup = await asyncio.to_thread(create_backup, settings)
    return ok(backup)


@router.get("/system/backups")
async def get_system_backups(
    settings: Settings = Depends(get_settings_dep),
    _user=Depends(require_auth),
):
    return ok(list_backups(settings))


@router.get("/system/backups/{filename}")
async def download_system_backup(
    filename: str,
    settings: Settings = Depends(get_settings_dep),
    _user=Depends(require_auth),
):
    path = resolve_backup(settings, filename)
    return FileResponse(path, media_type="application/zip", filename=path.name)
