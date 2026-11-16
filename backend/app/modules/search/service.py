"""Full-text and knowledge search.

SQLite uses FTS5; other databases fall back to LIKE. Search results always
return the concrete sentence and book/chapter provenance.
"""

from __future__ import annotations

from typing import Any

from sqlalchemy import String, or_, select, text
from sqlalchemy.exc import OperationalError
from sqlalchemy.ext.asyncio import AsyncSession

from app.database.fts import build_match_query, clean_snippet
from app.database.models import (
    Book, Chapter, HistoricalEntity, HistoricalEvent, Sentence, Translation,
)


def _snippet(value: str, query: str, radius: int = 70) -> str:
    if not value:
        return ""
    index = value.find(query)
    if index < 0:
        return value[: radius * 2]
    start = max(0, index - radius)
    end = min(len(value), index + len(query) + radius)
    prefix = "…" if start > 0 else ""
    suffix = "…" if end < len(value) else ""
    return f"{prefix}{value[start:end]}{suffix}"


async def _hydrate_text_hits(
    session: AsyncSession, hits: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    sentence_ids = list({hit["doc_id"] for hit in hits})
    if not sentence_ids:
        return []
    sentences = {
        row.id: row for row in (await session.scalars(
            select(Sentence).where(Sentence.id.in_(sentence_ids))
        )).all()
    }
    chapter_ids = list({row.chapter_id for row in sentences.values()})
    chapters = {
        row.id: row for row in (await session.scalars(
            select(Chapter).where(Chapter.id.in_(chapter_ids))
        )).all()
    } if chapter_ids else {}
    book_ids = list({row.book_id for row in sentences.values()})
    books = {
        row.id: row for row in (await session.scalars(
            select(Book).where(Book.id.in_(book_ids), Book.deleted_at.is_(None))
        )).all()
    } if book_ids else {}
    translations = {
        row.sentence_id: row for row in (await session.scalars(
            select(Translation).where(Translation.sentence_id.in_(sentence_ids))
        )).all()
    } if sentence_ids else {}

    results: list[dict[str, Any]] = []
    for hit in hits:
        sentence = sentences.get(hit["doc_id"])
        if sentence is None:
            continue
        book = books.get(sentence.book_id)
        if book is None:
            continue
        chapter = chapters.get(sentence.chapter_id)
        translation = translations.get(sentence.id)
        results.append({
            "sentence_id": sentence.id,
            "book_id": sentence.book_id,
            "book_title": book.title,
            "chapter_id": sentence.chapter_id,
            "chapter_title": chapter.title if chapter else None,
            "doc_type": hit["doc_type"],
            "original_text": sentence.original_text,
            "translation_text": translation.text if translation else None,
            "snippet": clean_snippet(hit.get("snip")) or _snippet(
                sentence.original_text if hit["doc_type"] == "original"
                else (translation.text if translation else sentence.original_text),
                "",
            ),
            "score": hit.get("score"),
        })
    return results


async def search_text(
    session: AsyncSession,
    query: str,
    *,
    scope: str = "all",
    book_id: str | None = None,
    limit: int = 30,
) -> list[dict[str, Any]]:
    match = build_match_query(query)
    if not match:
        return []
    clauses = ["search_fts MATCH :match"]
    params: dict[str, Any] = {"match": match, "limit": limit}
    if scope in {"original", "translation"}:
        clauses.append("doc_type = :doc_type")
        params["doc_type"] = scope
    if book_id:
        clauses.append("book_id = :book_id")
        params["book_id"] = book_id
    sql = (
        "SELECT doc_type, doc_id, title, "
        "snippet(search_fts, 5, '[[', ']]', '…', 14) AS snip, "
        "bm25(search_fts) AS score FROM search_fts "
        f"WHERE {' AND '.join(clauses)} ORDER BY score LIMIT :limit"
    )
    try:
        rows = (await session.execute(text(sql), params)).mappings().all()
        return await _hydrate_text_hits(session, [dict(row) for row in rows])
    except OperationalError:
        # Database without FTS5: run a bounded LIKE search.
        return await _fallback_text_search(
            session, query, scope=scope, book_id=book_id, limit=limit
        )


async def _fallback_text_search(
    session: AsyncSession,
    query: str,
    *,
    scope: str,
    book_id: str | None,
    limit: int,
) -> list[dict[str, Any]]:
    pattern = f"%{query}%"
    conditions = [Sentence.original_text.like(pattern)]
    if scope != "original":
        conditions.append(Sentence.id.in_(select(Translation.sentence_id).where(
            Translation.text.like(pattern)
        )))
    statement = select(Sentence).where(or_(*conditions))
    if book_id:
        statement = statement.where(Sentence.book_id == book_id)
    sentences = list((await session.scalars(statement.limit(limit))).all())
    translations = {
        row.sentence_id: row for row in (await session.scalars(
            select(Translation).where(Translation.sentence_id.in_([s.id for s in sentences]))
        )).all()
    } if sentences else {}
    hits = []
    for sentence in sentences:
        doc_type = "original"
        translation = translations.get(sentence.id)
        if scope != "original" and translation and query in translation.text and query not in sentence.original_text:
            doc_type = "translation"
        hits.append({
            "doc_type": doc_type,
            "doc_id": sentence.id,
            "snip": (
                _snippet(sentence.original_text, query) if doc_type == "original"
                else _snippet(translation.text if translation else "", query)
            ),
            "score": 0,
        })
    return await _hydrate_text_hits(session, hits)


async def search_entities(
    session: AsyncSession, query: str, *, limit: int = 10
) -> list[dict[str, Any]]:
    pattern = f"%{query}%"
    rows = list((await session.scalars(
        select(HistoricalEntity)
        .where(
            HistoricalEntity.deleted_at.is_(None),
            HistoricalEntity.status != "rejected",
            or_(
                HistoricalEntity.canonical_name.like(pattern),
                HistoricalEntity.aliases.cast(String).like(pattern),
                HistoricalEntity.summary.like(pattern),
            ),
        )
        .order_by(HistoricalEntity.canonical_name)
        .limit(limit)
    )).all())
    return [
        {
            "id": row.id,
            "canonical_name": row.canonical_name,
            "kind": row.kind,
            "dynasty": row.dynasty,
            "identity": row.identity,
            "summary": row.summary,
            "status": row.status,
        }
        for row in rows
    ]


async def search_events(
    session: AsyncSession, query: str, *, limit: int = 10
) -> list[dict[str, Any]]:
    pattern = f"%{query}%"
    rows = list((await session.scalars(
        select(HistoricalEvent)
        .where(
            HistoricalEvent.deleted_at.is_(None),
            HistoricalEvent.status != "rejected",
            or_(
                HistoricalEvent.name.like(pattern),
                HistoricalEvent.description.like(pattern),
                HistoricalEvent.time_raw.like(pattern),
            ),
        )
        .order_by(HistoricalEvent.time_start_year.asc().nulls_last())
        .limit(limit)
    )).all())
    return [
        {
            "id": row.id,
            "name": row.name,
            "event_type": row.event_type,
            "time_raw": row.time_raw,
            "time_start_year": row.time_start_year,
            "time_precision": row.time_precision,
            "status": row.status,
        }
        for row in rows
    ]
