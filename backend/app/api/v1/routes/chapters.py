"""Chapter reading endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_session, require_auth
from app.api.v1.serializers import serialize_book
from app.core.responses import ok
from app.core.utils import iso, utcnow
from app.database.models import Book
from app.modules.book_manager.queries import (
    chapter_translation_status, get_chapter, get_chapter_content,
)

router = APIRouter(tags=["chapters"], dependencies=[Depends(require_auth)])


@router.get("/chapters/{chapter_id}")
async def chapter_detail(
    chapter_id: str,
    session: AsyncSession = Depends(get_session),
):
    chapter = await get_chapter(session, chapter_id)
    book = await session.get(Book, chapter.book_id)
    status = await chapter_translation_status(session, chapter_id)
    return ok({
        "id": chapter.id,
        "book_id": chapter.book_id,
        "book_title": book.title if book else None,
        "ordinal": chapter.ordinal,
        "title": chapter.title,
        "paragraph_count": chapter.paragraph_count,
        "sentence_count": chapter.sentence_count,
        "translated_count": chapter.translated_count,
        "translation_status": status,
        "created_at": iso(chapter.created_at),
    })


@router.get("/chapters/{chapter_id}/paragraphs")
async def chapter_paragraphs(
    chapter_id: str,
    session: AsyncSession = Depends(get_session),
):
    return ok(await get_chapter_content(session, chapter_id))


@router.get("/chapters/{chapter_id}/content")
async def chapter_content(
    chapter_id: str,
    session: AsyncSession = Depends(get_session),
):
    return ok(await get_chapter_content(session, chapter_id))


@router.get("/chapters/{chapter_id}/translation-status")
async def translation_status(
    chapter_id: str,
    session: AsyncSession = Depends(get_session),
):
    return ok(await chapter_translation_status(session, chapter_id))


@router.get("/chapters/{chapter_id}/download")
async def download_chapter(
    chapter_id: str,
    session: AsyncSession = Depends(get_session),
):
    chapter = await get_chapter(session, chapter_id)
    book = await session.get(Book, chapter.book_id)
    content = await get_chapter_content(session, chapter_id)
    return ok({
        "format": "guwenreading.chapter.v1",
        "exported_at": iso(utcnow()),
        "book": serialize_book(book) if book else None,
        "chapter": content["chapter"],
        "paragraphs": content["paragraphs"],
        "previous_chapter_id": content["previous_chapter_id"],
        "next_chapter_id": content["next_chapter_id"],
    })
