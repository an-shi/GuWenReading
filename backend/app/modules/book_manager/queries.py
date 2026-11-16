"""Read/query services for the library and reader."""

from __future__ import annotations

import shutil
from typing import Any

from sqlalchemy import String, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.errors import AppError, ErrorCode, not_found
from app.core.utils import iso, utcnow
from app.database.models import (
    Book, Chapter, Paragraph, Sentence, Translation, TranslationReview,
)
from app.modules.book_manager.storage import resolve_data_path


async def get_book(session: AsyncSession, book_id: str, *, include_deleted: bool = False) -> Book:
    book = await session.get(Book, book_id)
    if book is None or (book.deleted_at is not None and not include_deleted):
        raise not_found("Book", book_id)
    return book


async def get_chapter(session: AsyncSession, chapter_id: str) -> Chapter:
    chapter = await session.get(Chapter, chapter_id)
    if chapter is None:
        raise not_found("Chapter", chapter_id)
    book = await session.get(Book, chapter.book_id)
    if book is None or book.deleted_at is not None:
        raise not_found("Chapter", chapter_id)
    return chapter


def _book_sort(sort: str):
    if sort == "title":
        return (Book.title.asc(),)
    if sort == "author":
        return (Book.author.asc().nulls_last(), Book.title.asc())
    if sort == "imported":
        return (Book.created_at.desc(),)
    return (Book.last_read_at.desc().nulls_last(), Book.created_at.desc())


async def list_books(
    session: AsyncSession,
    *,
    query: str | None = None,
    category: str | None = None,
    tag: str | None = None,
    sort: str = "recent",
    page: int = 1,
    page_size: int = 24,
) -> tuple[list[Book], int]:
    conditions = [Book.deleted_at.is_(None)]
    if query:
        pattern = f"%{query.strip()}%"
        conditions.append(or_(
            Book.title.like(pattern),
            Book.author.like(pattern),
            Book.description.like(pattern),
        ))
    if category:
        conditions.append(Book.category == category)
    if tag:
        conditions.append(Book.tags.cast(String).like(f'%"{tag}"%'))

    total = await session.scalar(select(func.count()).select_from(Book).where(*conditions)) or 0
    statement = (
        select(Book)
        .where(*conditions)
        .order_by(*_book_sort(sort))
        .offset((page - 1) * page_size)
        .limit(page_size)
    )
    books = list((await session.scalars(statement)).all())
    return books, total


async def list_chapters(session: AsyncSession, book_id: str) -> list[Chapter]:
    await get_book(session, book_id)
    statement = select(Chapter).where(Chapter.book_id == book_id).order_by(Chapter.ordinal)
    return list((await session.scalars(statement)).all())


async def chapter_translation_status(session: AsyncSession, chapter_id: str) -> dict[str, Any]:
    chapter = await get_chapter(session, chapter_id)
    rows = await session.execute(
        select(Sentence.translation_state, func.count())
        .where(Sentence.chapter_id == chapter_id)
        .group_by(Sentence.translation_state)
    )
    states = {state: count for state, count in rows.all()}
    total = await session.scalar(
        select(func.count()).select_from(Sentence).where(Sentence.chapter_id == chapter_id)
    ) or 0
    translated = await session.scalar(
        select(func.count()).select_from(Translation).where(Translation.chapter_id == chapter_id)
    ) or 0
    manual = await session.scalar(
        select(func.count()).select_from(Translation).where(
            Translation.chapter_id == chapter_id, Translation.origin == "manual"
        )
    ) or 0
    pending_reviews = await session.scalar(
        select(func.count()).select_from(TranslationReview)
        .join(Sentence, Sentence.id == TranslationReview.sentence_id)
        .where(Sentence.chapter_id == chapter_id, TranslationReview.status == "pending")
    ) or 0
    return {
        "chapter_id": chapter_id,
        "total": total,
        "translated": translated,
        "manual": manual,
        "pending_reviews": pending_reviews,
        "states": {
            "pending": states.get("pending", 0),
            "queued": states.get("queued", 0),
            "translating": states.get("translating", 0),
            "completed": states.get("completed", 0),
            "failed": states.get("failed", 0),
        },
        "percent": round((translated / total) * 100, 2) if total else 0.0,
        "updated_at": iso(chapter.updated_at),
    }


async def get_chapter_content(session: AsyncSession, chapter_id: str) -> dict[str, Any]:
    chapter = await get_chapter(session, chapter_id)
    book = await session.get(Book, chapter.book_id)
    paragraphs = list((await session.scalars(
        select(Paragraph).where(Paragraph.chapter_id == chapter_id).order_by(Paragraph.ordinal)
    )).all())
    sentences = list((await session.scalars(
        select(Sentence).where(Sentence.chapter_id == chapter_id).order_by(Sentence.ordinal)
    )).all())
    translations = list((await session.scalars(
        select(Translation).where(Translation.chapter_id == chapter_id)
    )).all())
    reviews = list((await session.scalars(
        select(TranslationReview)
        .join(Sentence, Sentence.id == TranslationReview.sentence_id)
        .where(Sentence.chapter_id == chapter_id, TranslationReview.status == "pending")
    )).all())

    translation_map = {row.sentence_id: row for row in translations}
    review_map = {row.sentence_id: row for row in reviews}
    by_paragraph: dict[str, list[dict[str, Any]]] = {}
    for sentence in sentences:
        translation = translation_map.get(sentence.id)
        review = review_map.get(sentence.id)
        state = "completed" if translation else sentence.translation_state
        by_paragraph.setdefault(sentence.paragraph_id, []).append({
            "id": sentence.id,
            "ordinal": sentence.ordinal,
            "original_text": sentence.original_text,
            "start_offset": sentence.start_offset,
            "end_offset": sentence.end_offset,
            "needs_review": sentence.needs_review,
            "split_confidence": sentence.split_confidence,
            "translation_state": state,
            "translation_error": sentence.translation_error,
            "translation": {
                "id": translation.id,
                "sentence_id": translation.sentence_id,
                "paragraph_id": translation.paragraph_id,
                "chapter_id": translation.chapter_id,
                "book_id": translation.book_id,
                "text": translation.text,
                "origin": translation.origin,
                "status": translation.status,
                "model_name": translation.model_name,
                "edited_at": iso(translation.edited_at),
                "version": translation.version,
            } if translation else None,
            "pending_review": {
                "id": review.id,
                "candidate_text": review.candidate_text,
            } if review else None,
        })

    paragraph_payload = []
    for paragraph in paragraphs:
        sentence_rows = by_paragraph.get(paragraph.id, [])
        translated_parts = [
            item["translation"]["text"] for item in sentence_rows if item["translation"]
        ]
        complete = bool(sentence_rows) and all(item["translation"] for item in sentence_rows)
        paragraph_payload.append({
            "id": paragraph.id,
            "ordinal": paragraph.ordinal,
            "original_text": paragraph.original_text,
            "start_offset": paragraph.start_offset,
            "end_offset": paragraph.end_offset,
            "sentence_count": paragraph.sentence_count,
            "sentences": sentence_rows,
            "translation_text": "".join(translated_parts) if translated_parts else None,
            "translation_complete": complete,
        })

    previous_id = await session.scalar(
        select(Chapter.id).where(
            Chapter.book_id == chapter.book_id, Chapter.ordinal < chapter.ordinal
        ).order_by(Chapter.ordinal.desc()).limit(1)
    )
    next_id = await session.scalar(
        select(Chapter.id).where(
            Chapter.book_id == chapter.book_id, Chapter.ordinal > chapter.ordinal
        ).order_by(Chapter.ordinal.asc()).limit(1)
    )

    status = await chapter_translation_status(session, chapter_id)
    return {
        "book": {
            "id": book.id,
            "title": book.title,
            "author": book.author,
            "source_format": book.source_format,
            "category": book.category,
        },
        "chapter": {
            "id": chapter.id,
            "book_id": chapter.book_id,
            "ordinal": chapter.ordinal,
            "title": chapter.title,
            "start_offset": chapter.start_offset,
            "end_offset": chapter.end_offset,
            "paragraph_count": chapter.paragraph_count,
            "sentence_count": chapter.sentence_count,
            "translated_count": chapter.translated_count,
        },
        "previous_chapter_id": previous_id,
        "next_chapter_id": next_id,
        "translation_status": status,
        "paragraphs": paragraph_payload,
    }


async def update_book(session: AsyncSession, book_id: str, values: dict[str, Any]) -> Book:
    book = await get_book(session, book_id)
    allowed = {"title", "author", "dynasty", "category", "description", "tags"}
    for key, value in values.items():
        if key in allowed and value is not None:
            if key == "title":
                value = str(value).strip()[:300]
                if not value:
                    raise AppError(ErrorCode.VALIDATION_ERROR, "Title cannot be empty", status_code=422)
            setattr(book, key, value)
    book.version += 1
    book.updated_at = utcnow()
    await session.commit()
    await session.refresh(book)
    return book


async def delete_book(
    session: AsyncSession, settings: Settings, book_id: str, *, permanent: bool = False
) -> None:
    book = await get_book(session, book_id, include_deleted=True)
    if permanent:
        book_dir = settings.books_dir / book.id
        await session.delete(book)
        await session.commit()
        shutil.rmtree(book_dir, ignore_errors=True)
        cover = resolve_data_path(settings, book.cover_path)
        if cover and cover.exists():
            cover.unlink(missing_ok=True)
        return
    book.deleted_at = utcnow()
    book.status = "deleted"
    book.version += 1
    await session.commit()


async def count_manual_translations(session: AsyncSession, book_id: str) -> int:
    return await session.scalar(
        select(func.count()).select_from(Translation).where(
            Translation.book_id == book_id, Translation.origin == "manual"
        )
    ) or 0
