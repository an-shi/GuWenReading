"""SQLite FTS5 full-text index.

Chinese text has no spaces, so both indexing and querying insert spaces between
CJK characters. This gives character-level phrase matching via unicode61 and
works on every SQLite build with FTS5 enabled. PostgreSQL deployments fall back
to ILIKE search (see search service).
"""

from __future__ import annotations

import re
from typing import Iterable

from sqlalchemy import bindparam, text
from sqlalchemy.exc import OperationalError
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession

CJK_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")
TOKEN_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]|[A-Za-z0-9_]+")


def tokenize_cjk(value: str) -> str:
    """Space-separate CJK characters while keeping latin words intact."""
    out: list[str] = []
    for char in value:
        if CJK_RE.match(char):
            out.append(f" {char} ")
        else:
            out.append(char)
    return re.sub(r"\s+", " ", "".join(out)).strip()


def build_match_query(value: str) -> str:
    tokens = TOKEN_RE.findall(value)
    if not tokens:
        return ""
    # Group consecutive CJK characters into adjacency phrases.
    phrases: list[str] = []
    cjk_buffer: list[str] = []

    def flush() -> None:
        if cjk_buffer:
            phrases.append('"' + " ".join(cjk_buffer) + '"')
            cjk_buffer.clear()

    for token in tokens:
        if len(token) == 1 and CJK_RE.match(token):
            cjk_buffer.append(token)
        else:
            flush()
            phrases.append('"' + token.replace('"', "") + '"')
    flush()
    return " AND ".join(p for p in phrases if p != '""')


def clean_snippet(value: str | None) -> str:
    if not value:
        return ""
    # Undo the spacing introduced for indexing, only around CJK characters.
    value = re.sub(
        r"(?<=[\u3400-\u9fff])\s+(?=[\u3400-\u9fff，。！？；：、“”‘’（）《》…])",
        "",
        value,
    )
    value = re.sub(
        r"(?<=[，。！？；：、“”‘’（）《》…])\s+(?=[\u3400-\u9fff])",
        "",
        value,
    )
    return value


def _is_sqlite(engine: AsyncEngine) -> bool:
    return "sqlite" in (engine.url.drivername or "")


async def ensure_fts(engine: AsyncEngine) -> bool:
    if not _is_sqlite(engine):
        return False
    async with engine.begin() as conn:
        try:
            await conn.execute(text(
                "CREATE VIRTUAL TABLE IF NOT EXISTS search_fts USING fts5("
                "doc_type UNINDEXED, doc_id UNINDEXED, book_id UNINDEXED, "
                "chapter_id UNINDEXED, title, body, tokenize='unicode61 remove_diacritics 2')"
            ))
        except OperationalError:
            return False
    return True


async def delete_sentence_index(session: AsyncSession, sentence_id: str) -> None:
    await session.execute(
        text("DELETE FROM search_fts WHERE doc_id = :sid"), {"sid": sentence_id}
    )


async def index_sentence(
    session: AsyncSession,
    *,
    sentence_id: str,
    book_id: str,
    chapter_id: str,
    title: str,
    original_text: str,
    translated_text: str | None = None,
) -> None:
    try:
        await delete_sentence_index(session, sentence_id)
        await session.execute(
            text(
                "INSERT INTO search_fts(doc_type, doc_id, book_id, chapter_id, title, body) "
                "VALUES (:doc_type, :doc_id, :book_id, :chapter_id, :title, :body)"
            ),
            {
                "doc_type": "original", "doc_id": sentence_id, "book_id": book_id,
                "chapter_id": chapter_id, "title": tokenize_cjk(title),
                "body": tokenize_cjk(original_text),
            },
        )
        if translated_text:
            await session.execute(
                text(
                    "INSERT INTO search_fts(doc_type, doc_id, book_id, chapter_id, title, body) "
                    "VALUES (:doc_type, :doc_id, :book_id, :chapter_id, :title, :body)"
                ),
                {
                    "doc_type": "translation", "doc_id": sentence_id, "book_id": book_id,
                    "chapter_id": chapter_id, "title": tokenize_cjk(title),
                    "body": tokenize_cjk(translated_text),
                },
            )
    except OperationalError:
        # FTS index is a search accelerator; never break the write path.
        return


async def bulk_index_sentences(
    session: AsyncSession,
    rows: Iterable[dict],
) -> None:
    payload = []
    for row in rows:
        title = tokenize_cjk(row["title"])
        payload.append({
            "doc_type": "original", "doc_id": row["sentence_id"], "book_id": row["book_id"],
            "chapter_id": row["chapter_id"], "title": title,
            "body": tokenize_cjk(row["original_text"]),
        })
    if not payload:
        return
    try:
        # Delete stale rows for these sentences first (re-import safety).
        ids = [row["doc_id"] for row in payload]
        await session.execute(
            text("DELETE FROM search_fts WHERE doc_id IN :ids").bindparams(
                bindparam("ids", expanding=True)
            ),
            {"ids": ids},
        )
        await session.execute(
            text(
                "INSERT INTO search_fts(doc_type, doc_id, book_id, chapter_id, title, body) "
                "VALUES (:doc_type, :doc_id, :book_id, :chapter_id, :title, :body)"
            ),
            payload,
        )
    except OperationalError:
        return


async def backfill_fts(session: AsyncSession) -> int:
    """Index existing sentences and translations once, for upgraded libraries."""
    from sqlalchemy import select

    from app.database.models import Book, Chapter, Sentence, Translation

    try:
        existing = await session.scalar(text("SELECT COUNT(*) FROM search_fts"))
    except OperationalError:
        return 0
    if existing:
        return 0

    indexed = 0
    offset = 0
    while True:
        rows = (await session.execute(
            select(Sentence, Chapter, Book)
            .join(Chapter, Chapter.id == Sentence.chapter_id)
            .join(Book, Book.id == Sentence.book_id)
            .where(Book.deleted_at.is_(None))
            .order_by(Sentence.id)
            .limit(500)
            .offset(offset)
        )).all()
        if not rows:
            break
        payload = [
            {
                "doc_type": "original", "doc_id": sentence.id,
                "book_id": sentence.book_id, "chapter_id": sentence.chapter_id,
                "title": tokenize_cjk(f"{book.title} · {chapter.title}"),
                "body": tokenize_cjk(sentence.original_text),
            }
            for sentence, chapter, book in rows
        ]
        await session.execute(
            text(
                "INSERT INTO search_fts(doc_type, doc_id, book_id, chapter_id, title, body) "
                "VALUES (:doc_type, :doc_id, :book_id, :chapter_id, :title, :body)"
            ),
            payload,
        )
        await session.commit()
        indexed += len(payload)
        offset += len(rows)

    offset = 0
    while True:
        rows = (await session.execute(
            select(Translation, Sentence, Chapter, Book)
            .join(Sentence, Sentence.id == Translation.sentence_id)
            .join(Chapter, Chapter.id == Sentence.chapter_id)
            .join(Book, Book.id == Sentence.book_id)
            .where(Book.deleted_at.is_(None), Translation.deleted_at.is_(None))
            .order_by(Translation.id)
            .limit(500)
            .offset(offset)
        )).all()
        if not rows:
            break
        payload = [
            {
                "doc_type": "translation", "doc_id": sentence.id,
                "book_id": sentence.book_id, "chapter_id": sentence.chapter_id,
                "title": tokenize_cjk(f"{book.title} · {chapter.title}"),
                "body": tokenize_cjk(translation.text),
            }
            for translation, sentence, chapter, book in rows
        ]
        await session.execute(
            text(
                "INSERT INTO search_fts(doc_type, doc_id, book_id, chapter_id, title, body) "
                "VALUES (:doc_type, :doc_id, :book_id, :chapter_id, :title, :body)"
            ),
            payload,
        )
        await session.commit()
        indexed += len(payload)
        offset += len(rows)
    return indexed
