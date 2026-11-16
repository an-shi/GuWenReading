"""Book library endpoints."""

from __future__ import annotations

import asyncio
from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, Query, Request, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_session, get_settings_dep, require_auth
from app.api.v1.schemas import BookUpdate
from app.api.v1.serializers import serialize_book
from app.core.config import Settings
from app.core.errors import AppError, ErrorCode
from app.core.responses import ok, page_data
from app.core.utils import new_id, safe_filename
from app.database.models import Chapter
from app.modules.book_manager.queries import (
    delete_book, get_book, list_books, update_book,
)
from app.modules.book_manager.service import BookImportService, ImportOptions
from app.modules.book_manager.storage import guess_media_type, resolve_data_path

router = APIRouter(tags=["books"], dependencies=[Depends(require_auth)])


@router.get("/books")
async def get_books(
    q: str | None = Query(default=None),
    category: str | None = Query(default=None),
    tag: str | None = Query(default=None),
    sort: str = Query(default="recent", pattern="^(recent|imported|title|author)$"),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=24, ge=1, le=100),
    session: AsyncSession = Depends(get_session),
):
    books, total = await list_books(
        session, query=q, category=category, tag=tag, sort=sort, page=page, page_size=page_size
    )
    return ok(page_data([serialize_book(book) for book in books], total, page, page_size))


async def _write_upload(file: UploadFile, destination: Path, max_bytes: int) -> None:
    total = 0
    with destination.open("wb") as handle:
        while True:
            chunk = await file.read(1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > max_bytes:
                raise AppError(
                    ErrorCode.FILE_TOO_LARGE,
                    f"File exceeds the {max_bytes // (1024 * 1024)} MB limit",
                    status_code=413,
                )
            handle.write(chunk)
    if total == 0:
        raise AppError(ErrorCode.VALIDATION_ERROR, "Uploaded file is empty", status_code=422)


@router.post("/books/import", status_code=201)
async def import_book(
    request: Request,
    file: UploadFile = File(...),
    title: str | None = Form(default=None),
    author: str | None = Form(default=None),
    dynasty: str | None = Form(default=None),
    category: str | None = Form(default=None),
    description: str | None = Form(default=None),
    tags: str | None = Form(default=None),
    session: AsyncSession = Depends(get_session),
    settings: Settings = Depends(get_settings_dep),
):
    filename = safe_filename(file.filename or "book.txt")
    suffix = Path(filename).suffix.lower()
    if suffix not in {".txt", ".epub", ".docx", ".pdf"}:
        raise AppError(
            ErrorCode.UNSUPPORTED_FORMAT,
            "Only TXT, EPUB, DOCX and PDF files are supported",
            status_code=415,
        )
    temp_path = settings.tmp_dir / f"import-{new_id()}{suffix}"
    try:
        await _write_upload(file, temp_path, settings.max_upload_mb * 1024 * 1024)
        tag_list = [
            item.strip() for item in (tags or "").replace("，", ",").split(",") if item.strip()
        ]
        book = await BookImportService(settings).import_book(
            session,
            temp_path,
            filename,
            ImportOptions(
                title=title, author=author, dynasty=dynasty, category=category,
                description=description, tags=tag_list,
            ),
        )
        # Reading/listing should never depend on a stale identity map.
        await session.refresh(book)
    finally:
        await asyncio.to_thread(temp_path.unlink, missing_ok=True)
        await file.close()
    return ok(serialize_book(book), message="imported")


@router.get("/books/{book_id}")
async def get_book_detail(
    book_id: str,
    session: AsyncSession = Depends(get_session),
):
    book = await get_book(session, book_id)
    payload = serialize_book(book)
    payload["warnings"] = (book.metadata_json or {}).get("warnings", [])
    return ok(payload)


@router.put("/books/{book_id}")
async def edit_book(
    book_id: str,
    body: BookUpdate,
    session: AsyncSession = Depends(get_session),
):
    values = body.model_dump(exclude_unset=True, exclude_none=True)
    if "tags" in values and values["tags"] is not None:
        values["tags"] = [tag.strip() for tag in values["tags"] if tag.strip()]
    book = await update_book(session, book_id, values)
    return ok(serialize_book(book))


@router.delete("/books/{book_id}")
async def remove_book(
    book_id: str,
    permanent: bool = Query(default=False),
    session: AsyncSession = Depends(get_session),
    settings: Settings = Depends(get_settings_dep),
):
    await delete_book(session, settings, book_id, permanent=permanent)
    return ok({"id": book_id, "removed": True, "permanent": permanent})


@router.post("/books/{book_id}/reparse")
async def reparse_book(
    book_id: str,
    force: bool = Query(default=False),
    session: AsyncSession = Depends(get_session),
    settings: Settings = Depends(get_settings_dep),
):
    book = await get_book(session, book_id)
    updated = await BookImportService(settings).reparse(session, book, force=force)
    return ok(serialize_book(updated), message="reparsed")


@router.get("/books/{book_id}/cover")
async def book_cover(
    book_id: str,
    session: AsyncSession = Depends(get_session),
    settings: Settings = Depends(get_settings_dep),
):
    book = await get_book(session, book_id)
    path = resolve_data_path(settings, book.cover_path)
    if path is None or not path.exists():
        raise AppError(ErrorCode.NOT_FOUND, "Cover not found", status_code=404)
    return FileResponse(path, media_type=guess_media_type(path))


@router.get("/books/{book_id}/original")
async def book_original(
    book_id: str,
    session: AsyncSession = Depends(get_session),
    settings: Settings = Depends(get_settings_dep),
):
    book = await get_book(session, book_id)
    path = resolve_data_path(settings, book.original_path)
    if path is None or not path.exists():
        raise AppError(ErrorCode.NOT_FOUND, "Original file is missing", status_code=404)
    return FileResponse(path, media_type="application/octet-stream", filename=book.source_filename)


@router.get("/books/{book_id}/manifest")
async def book_manifest(
    book_id: str,
    session: AsyncSession = Depends(get_session),
):
    book = await get_book(session, book_id)
    chapters = list((await session.scalars(
        select(Chapter).where(Chapter.book_id == book_id).order_by(Chapter.ordinal)
    )).all())
    return ok({
        "book": serialize_book(book),
        "chapters": [
            {
                "id": chapter.id,
                "ordinal": chapter.ordinal,
                "title": chapter.title,
                "paragraph_count": chapter.paragraph_count,
                "sentence_count": chapter.sentence_count,
                "translated_count": chapter.translated_count,
            }
            for chapter in chapters
        ],
        "download": {
            "format": book.source_format,
            "file_size": book.file_size,
            "chapter_endpoint": "/api/v1/chapters/{chapter_id}/download",
        },
    })


@router.get("/books/{book_id}/chapters")
async def get_book_chapters(
    book_id: str,
    session: AsyncSession = Depends(get_session),
):
    from app.modules.book_manager.queries import list_chapters

    chapters = await list_chapters(session, book_id)
    return ok([
        {
            "id": chapter.id,
            "book_id": chapter.book_id,
            "ordinal": chapter.ordinal,
            "title": chapter.title,
            "paragraph_count": chapter.paragraph_count,
            "sentence_count": chapter.sentence_count,
            "translated_count": chapter.translated_count,
            "translation_percent": round(
                chapter.translated_count / chapter.sentence_count * 100, 2
            ) if chapter.sentence_count else 0.0,
        }
        for chapter in chapters
    ])
