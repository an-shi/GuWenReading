"""Book import: managed copies, canonical extracted text, offsets and indexing."""

from __future__ import annotations

import asyncio
import shutil
from dataclasses import dataclass, field
from pathlib import Path

from sqlalchemy import delete, func, insert, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.errors import AppError, ErrorCode
from app.core.logging import get_logger
from app.core.utils import new_id, normalize_text, safe_filename, sha256_file, utcnow
from app.database.fts import bulk_index_sentences
from app.database.models import Book, Chapter, Paragraph, Sentence
from app.modules.book_manager.storage import image_extension, managed_relative
from app.modules.document_parser import parse_document
from app.modules.document_parser.registry import detect_format
from app.modules.text_processor.splitter import split_sentences

logger = get_logger(__name__)


@dataclass
class ImportOptions:
    title: str | None = None
    author: str | None = None
    dynasty: str | None = None
    category: str | None = None
    description: str | None = None
    tags: list[str] = field(default_factory=list)


@dataclass
class BuiltText:
    text: str
    chapters: list[dict]
    paragraphs: list[dict]
    sentences: list[dict]
    chapter_count: int
    paragraph_count: int
    sentence_count: int


def build_document(parsed, book_id: str) -> BuiltText:
    """Flatten parsed chapters into canonical text and offset-bearing rows."""
    parts: list[str] = []
    cursor = 0
    chapters: list[dict] = []
    paragraphs: list[dict] = []
    sentences: list[dict] = []

    def append(value: str) -> None:
        nonlocal cursor
        parts.append(value)
        cursor += len(value)

    for chapter_ordinal, chapter in enumerate(parsed.chapters):
        chapter_id = new_id()
        chapter_title = (chapter.title or f"第 {chapter_ordinal + 1} 章").strip()
        chapter_start = cursor
        append(chapter_title + "\n\n")

        paragraph_count = 0
        sentence_count = 0
        for paragraph_ordinal, raw_text in enumerate(chapter.paragraphs):
            text = raw_text.strip()
            if not text:
                continue
            paragraph_id = new_id()
            paragraph_start = cursor
            append(text)
            paragraph_end = cursor
            append("\n\n")

            spans = split_sentences(text, base_offset=paragraph_start)
            for sentence_ordinal, span in enumerate(spans):
                sentences.append({
                    "id": new_id(),
                    "book_id": book_id,
                    "chapter_id": chapter_id,
                    "paragraph_id": paragraph_id,
                    "ordinal": sentence_ordinal,
                    "original_text": span.text,
                    "normalized_text": normalize_text(span.text),
                    "start_offset": span.start,
                    "end_offset": span.end,
                    "char_count": len(span.text),
                    "needs_review": span.needs_review,
                    "split_confidence": span.confidence,
                    "translation_state": "pending",
                })
            sentence_count += len(spans)

            paragraphs.append({
                "id": paragraph_id,
                "book_id": book_id,
                "chapter_id": chapter_id,
                "ordinal": paragraph_count,
                "original_text": text,
                "normalized_text": normalize_text(text),
                "start_offset": paragraph_start,
                "end_offset": paragraph_end,
                "sentence_count": len(spans),
            })
            paragraph_count += 1

        chapter_end = cursor
        chapters.append({
            "id": chapter_id,
            "book_id": book_id,
            "ordinal": chapter_ordinal,
            "title": chapter_title,
            "source_title": chapter.source_title,
            "start_offset": chapter_start,
            "end_offset": chapter_end,
            "paragraph_count": paragraph_count,
            "sentence_count": sentence_count,
            "translated_count": 0,
        })

    return BuiltText(
        text="".join(parts),
        chapters=chapters,
        paragraphs=paragraphs,
        sentences=sentences,
        chapter_count=len(chapters),
        paragraph_count=len(paragraphs),
        sentence_count=len(sentences),
    )


class BookImportService:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    async def import_book(
        self,
        session: AsyncSession,
        temp_path: Path,
        filename: str,
        options: ImportOptions | None = None,
    ) -> Book:
        options = options or ImportOptions()
        filename = safe_filename(filename)
        source_format = detect_format(temp_path, filename)
        content_hash = await asyncio.to_thread(sha256_file, temp_path)

        existing = await session.scalar(
            select(Book).where(Book.content_hash == content_hash)
        )
        if existing is not None:
            raise AppError(
                ErrorCode.DUPLICATE_BOOK,
                "This file has already been imported",
                status_code=409,
                details={
                    "book_id": existing.id,
                    "title": existing.title,
                    "deleted": existing.deleted_at is not None,
                },
            )

        parsed = await asyncio.to_thread(parse_document, temp_path, filename)
        book_id = new_id()
        built = build_document(parsed, book_id)
        if built.sentence_count == 0:
            raise AppError(ErrorCode.PARSE_ERROR, "No readable sentences found", status_code=422)

        title = (options.title or parsed.metadata.get("title") or Path(filename).stem).strip()
        author = (options.author or parsed.metadata.get("author") or None)
        if author:
            author = author.strip() or None
        dynasty = (options.dynasty or parsed.metadata.get("dynasty") or None)

        book_dir = self.settings.books_dir / book_id
        source_dir = book_dir / "source"
        source_dir.mkdir(parents=True, exist_ok=False)
        stored_name = safe_filename(filename)
        original_path = source_dir / stored_name
        extracted_path = book_dir / "extracted.txt"
        cover_path: Path | None = None

        book = Book(
            id=book_id,
            title=title[:300],
            author=author[:200] if author else None,
            dynasty=dynasty[:100] if dynasty else None,
            category=options.category,
            description=options.description,
            tags=options.tags,
            source_format=source_format,
            source_filename=stored_name,
            original_path="",
            extracted_path=None,
            content_hash=content_hash,
            file_size=temp_path.stat().st_size,
            status="ready",
            metadata_json={
                "parser": parsed.metadata,
                "warnings": parsed.warnings,
                "text_encoding": parsed.metadata.get("extra", {}).get("text_encoding"),
            },
            chapter_count=built.chapter_count,
            paragraph_count=built.paragraph_count,
            sentence_count=built.sentence_count,
            translated_sentence_count=0,
        )

        try:
            await asyncio.to_thread(shutil.copy2, temp_path, original_path)
            extracted_path.write_text(built.text, encoding="utf-8")
            if parsed.cover:
                extension = image_extension(parsed.cover)
                if extension:
                    cover_path = self.settings.covers_dir / f"{book_id}{extension}"
                    cover_path.write_bytes(parsed.cover)

            book.original_path = managed_relative(self.settings, original_path)
            book.extracted_path = managed_relative(self.settings, extracted_path)
            if cover_path:
                book.cover_path = managed_relative(self.settings, cover_path)

            session.add(book)
            await session.flush()
            await session.execute(insert(Chapter), built.chapters)
            await session.execute(insert(Paragraph), built.paragraphs)
            await session.execute(insert(Sentence), built.sentences)

            chapter_titles = {chapter["id"]: chapter["title"] for chapter in built.chapters}
            fts_rows = [
                {
                    "sentence_id": row["id"],
                    "book_id": book_id,
                    "chapter_id": row["chapter_id"],
                    "title": f"{title} · {chapter_titles[row['chapter_id']]}",
                    "original_text": row["original_text"],
                }
                for row in built.sentences
            ]
            await bulk_index_sentences(session, fts_rows)
            await session.commit()
        except Exception:
            await session.rollback()
            shutil.rmtree(book_dir, ignore_errors=True)
            if cover_path and cover_path.exists():
                cover_path.unlink(missing_ok=True)
            raise

        logger.info(
            "book_imported",
            book_id=book_id,
            title=title,
            format=source_format,
            sentences=built.sentence_count,
        )
        await session.refresh(book)
        return book

    async def reparse(
        self, session: AsyncSession, book: Book, *, force: bool = False
    ) -> Book:
        from app.modules.book_manager.storage import resolve_data_path

        original = resolve_data_path(self.settings, book.original_path)
        if original is None or not original.exists():
            raise AppError(ErrorCode.NOT_FOUND, "Original book file is missing", status_code=410)

        from app.database.models import Translation

        translation_count = await session.scalar(
            select(func.count()).select_from(Translation).where(Translation.book_id == book.id)
        ) or 0
        if translation_count > 0 and not force:
            raise AppError(
                ErrorCode.REPARSE_BLOCKED,
                "This book already has translations. Re-parsing would remove them. "
                "Pass force=true to proceed and archive the current translations first.",
                status_code=409,
                details={"translations": translation_count},
            )

        if translation_count > 0 and force:
            from app.database.models import TranslationVersion

            rows = (await session.execute(
                select(Translation).where(Translation.book_id == book.id)
            )).scalars().all()
            for row in rows:
                session.add(TranslationVersion(
                    translation_id=None,
                    sentence_id=row.sentence_id,
                    text=row.text,
                    origin=row.origin,
                    model_name=row.model_name,
                    prompt_version=row.prompt_version,
                    note="archived before re-parse",
                ))
            await session.execute(delete(Translation).where(Translation.book_id == book.id))

        parsed = await asyncio.to_thread(parse_document, original, book.source_filename)
        built = build_document(parsed, book.id)
        if built.sentence_count == 0:
            raise AppError(ErrorCode.PARSE_ERROR, "No readable sentences after re-parsing", status_code=422)

        await session.execute(delete(Chapter).where(Chapter.book_id == book.id))
        await session.execute(delete(Sentence).where(Sentence.book_id == book.id))
        await session.flush()
        await session.execute(insert(Chapter), built.chapters)
        await session.execute(insert(Paragraph), built.paragraphs)
        await session.execute(insert(Sentence), built.sentences)

        extracted = resolve_data_path(self.settings, book.extracted_path) if book.extracted_path else None
        if extracted:
            extracted.write_text(built.text, encoding="utf-8")

        book.chapter_count = built.chapter_count
        book.paragraph_count = built.paragraph_count
        book.sentence_count = built.sentence_count
        book.translated_sentence_count = 0
        book.status = "ready"
        book.parse_error = None
        book.version += 1
        book.updated_at = utcnow()

        from sqlalchemy import text

        try:
            await session.execute(
                text("DELETE FROM search_fts WHERE book_id = :book_id"), {"book_id": book.id}
            )
        except Exception:
            pass
        chapter_titles = {chapter["id"]: chapter["title"] for chapter in built.chapters}
        await bulk_index_sentences(session, [
            {
                "sentence_id": row["id"],
                "book_id": book.id,
                "chapter_id": row["chapter_id"],
                "title": f"{book.title} · {chapter_titles[row['chapter_id']]}",
                "original_text": row["original_text"],
            }
            for row in built.sentences
        ])
        await session.commit()
        await session.refresh(book)
        return book
