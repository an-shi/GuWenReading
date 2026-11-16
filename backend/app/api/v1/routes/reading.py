"""Reading progress, annotations and bookmarks."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_session, require_auth
from app.api.v1.schemas import (
    AnnotationCreate, AnnotationUpdate, BookmarkCreate, ReadingProgressUpdate,
)
from app.core.errors import AppError, ErrorCode, not_found
from app.core.responses import ok, page_data
from app.core.utils import iso, new_id, utcnow
from app.database.models import Annotation, Bookmark, Chapter, ReadingProgress, Sentence
from app.modules.book_manager.queries import get_book

router = APIRouter(tags=["reading"], dependencies=[Depends(require_auth)])


def _progress_dict(row: ReadingProgress) -> dict:
    return {
        "id": row.id,
        "book_id": row.book_id,
        "device_id": row.device_id,
        "chapter_id": row.chapter_id,
        "paragraph_id": row.paragraph_id,
        "sentence_id": row.sentence_id,
        "position_ratio": row.position_ratio,
        "updated_at": iso(row.updated_at),
    }


@router.get("/reading-progress")
async def list_progress(
    book_id: str | None = Query(default=None),
    device_id: str | None = Query(default=None),
    session: AsyncSession = Depends(get_session),
):
    statement = select(ReadingProgress).where(ReadingProgress.deleted_at.is_(None))
    if book_id:
        statement = statement.where(ReadingProgress.book_id == book_id)
    if device_id:
        statement = statement.where(ReadingProgress.device_id == device_id)
    rows = list((await session.scalars(
        statement.order_by(ReadingProgress.updated_at.desc())
    )).all())
    return ok([_progress_dict(row) for row in rows])


@router.get("/reading-progress/{book_id}")
async def get_progress(
    book_id: str,
    device_id: str = Query(default="local"),
    session: AsyncSession = Depends(get_session),
):
    await get_book(session, book_id)
    row = await session.scalar(
        select(ReadingProgress).where(
            ReadingProgress.book_id == book_id,
            ReadingProgress.device_id == device_id,
            ReadingProgress.deleted_at.is_(None),
        )
    )
    return ok({"progress": _progress_dict(row) if row else None})


@router.put("/reading-progress")
async def save_progress(
    body: ReadingProgressUpdate,
    session: AsyncSession = Depends(get_session),
):
    book = await get_book(session, body.book_id)
    if body.chapter_id:
        chapter = await session.get(Chapter, body.chapter_id)
        if chapter is None or chapter.book_id != book.id:
            raise AppError(ErrorCode.VALIDATION_ERROR, "Chapter does not belong to this book", status_code=422)
    if body.sentence_id:
        sentence = await session.get(Sentence, body.sentence_id)
        if sentence is None or sentence.book_id != book.id:
            raise AppError(ErrorCode.VALIDATION_ERROR, "Sentence does not belong to this book", status_code=422)

    row = await session.scalar(
        select(ReadingProgress).where(
            ReadingProgress.book_id == book.id,
            ReadingProgress.device_id == body.device_id,
        )
    )
    if row is None:
        row = ReadingProgress(
            id=new_id(),
            book_id=book.id,
            device_id=body.device_id,
            chapter_id=body.chapter_id,
            paragraph_id=body.paragraph_id,
            sentence_id=body.sentence_id,
            position_ratio=body.position_ratio,
        )
        session.add(row)
    else:
        row.chapter_id = body.chapter_id or row.chapter_id
        row.paragraph_id = body.paragraph_id or row.paragraph_id
        row.sentence_id = body.sentence_id or row.sentence_id
        row.position_ratio = body.position_ratio
        row.deleted_at = None
        row.version += 1
        row.updated_at = utcnow()
    book.last_read_at = utcnow()
    await session.commit()
    await session.refresh(row)
    return ok(_progress_dict(row))


def _annotation_dict(row: Annotation) -> dict:
    return {
        "id": row.id,
        "book_id": row.book_id,
        "chapter_id": row.chapter_id,
        "paragraph_id": row.paragraph_id,
        "sentence_id": row.sentence_id,
        "quote": row.quote,
        "content": row.content,
        "color": row.color,
        "tags": row.tags or [],
        "device_id": row.device_id,
        "created_at": iso(row.created_at),
        "updated_at": iso(row.updated_at),
        "version": row.version,
    }


@router.get("/annotations")
async def list_annotations(
    book_id: str | None = Query(default=None),
    chapter_id: str | None = Query(default=None),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=100, ge=1, le=500),
    session: AsyncSession = Depends(get_session),
):
    conditions = [Annotation.deleted_at.is_(None)]
    if book_id:
        conditions.append(Annotation.book_id == book_id)
    if chapter_id:
        conditions.append(Annotation.chapter_id == chapter_id)
    rows = list((await session.scalars(
        select(Annotation).where(*conditions)
        .order_by(Annotation.created_at.desc())
        .offset((page - 1) * page_size).limit(page_size)
    )).all())
    return ok(page_data([_annotation_dict(row) for row in rows], len(rows), page, page_size))


@router.post("/annotations", status_code=201)
async def create_annotation(
    body: AnnotationCreate,
    session: AsyncSession = Depends(get_session),
):
    book = await get_book(session, body.book_id)
    if body.chapter_id:
        chapter = await session.get(Chapter, body.chapter_id)
        if chapter is None or chapter.book_id != book.id:
            raise AppError(ErrorCode.VALIDATION_ERROR, "Chapter does not belong to this book", status_code=422)
    row = Annotation(
        id=new_id(),
        book_id=book.id,
        chapter_id=body.chapter_id,
        paragraph_id=body.paragraph_id,
        sentence_id=body.sentence_id,
        quote=body.quote,
        content=body.content.strip(),
        color=body.color,
        tags=[tag.strip() for tag in body.tags if tag.strip()],
        device_id=body.device_id,
    )
    session.add(row)
    await session.commit()
    await session.refresh(row)
    return ok(_annotation_dict(row))


@router.put("/annotations/{annotation_id}")
async def update_annotation(
    annotation_id: str,
    body: AnnotationUpdate,
    session: AsyncSession = Depends(get_session),
):
    row = await session.get(Annotation, annotation_id)
    if row is None or row.deleted_at is not None:
        raise not_found("Annotation", annotation_id)
    if body.content is not None:
        row.content = body.content.strip()
    if body.color is not None:
        row.color = body.color
    if body.tags is not None:
        row.tags = [tag.strip() for tag in body.tags if tag.strip()]
    row.version += 1
    row.updated_at = utcnow()
    await session.commit()
    await session.refresh(row)
    return ok(_annotation_dict(row))


@router.delete("/annotations/{annotation_id}")
async def delete_annotation(annotation_id: str, session: AsyncSession = Depends(get_session)):
    row = await session.get(Annotation, annotation_id)
    if row is None or row.deleted_at is not None:
        raise not_found("Annotation", annotation_id)
    row.deleted_at = utcnow()
    row.version += 1
    await session.commit()
    return ok({"id": annotation_id, "removed": True})


def _bookmark_dict(row: Bookmark) -> dict:
    return {
        "id": row.id,
        "book_id": row.book_id,
        "chapter_id": row.chapter_id,
        "paragraph_id": row.paragraph_id,
        "sentence_id": row.sentence_id,
        "label": row.label,
        "position_ratio": row.position_ratio,
        "device_id": row.device_id,
        "created_at": iso(row.created_at),
        "updated_at": iso(row.updated_at),
    }


@router.get("/bookmarks")
async def list_bookmarks(
    book_id: str | None = Query(default=None),
    session: AsyncSession = Depends(get_session),
):
    statement = select(Bookmark).where(Bookmark.deleted_at.is_(None))
    if book_id:
        statement = statement.where(Bookmark.book_id == book_id)
    rows = list((await session.scalars(statement.order_by(Bookmark.created_at.desc()))).all())
    return ok([_bookmark_dict(row) for row in rows])


@router.post("/bookmarks", status_code=201)
async def create_bookmark(
    body: BookmarkCreate,
    session: AsyncSession = Depends(get_session),
):
    book = await get_book(session, body.book_id)
    chapter = await session.get(Chapter, body.chapter_id)
    if chapter is None or chapter.book_id != book.id:
        raise AppError(ErrorCode.VALIDATION_ERROR, "Chapter does not belong to this book", status_code=422)
    row = Bookmark(
        id=new_id(),
        book_id=book.id,
        chapter_id=chapter.id,
        paragraph_id=body.paragraph_id,
        sentence_id=body.sentence_id,
        label=body.label,
        position_ratio=body.position_ratio,
        device_id=body.device_id,
    )
    session.add(row)
    await session.commit()
    await session.refresh(row)
    return ok(_bookmark_dict(row))


@router.delete("/bookmarks/{bookmark_id}")
async def delete_bookmark(bookmark_id: str, session: AsyncSession = Depends(get_session)):
    row = await session.get(Bookmark, bookmark_id)
    if row is None or row.deleted_at is not None:
        raise not_found("Bookmark", bookmark_id)
    row.deleted_at = utcnow()
    row.version += 1
    await session.commit()
    return ok({"id": bookmark_id, "removed": True})
