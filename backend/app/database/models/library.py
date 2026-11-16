"""Books, chapters, paragraphs and sentences.

Sentence rows keep character offsets into the managed extracted text so that
原文 can always be traced exactly. Translations never mutate these tables.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from sqlalchemy import (
    JSON, DateTime, Float, ForeignKey, Index, Integer, String, Text, UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.utils import utcnow
from app.database.base import Base, IdMixin, SyncMixin


class Book(IdMixin, SyncMixin, Base):
    __tablename__ = "books"

    title: Mapped[str] = mapped_column(String(300), nullable=False, index=True)
    author: Mapped[str | None] = mapped_column(String(200))
    dynasty: Mapped[str | None] = mapped_column(String(100))
    category: Mapped[str | None] = mapped_column(String(100), index=True)
    description: Mapped[str | None] = mapped_column(Text)
    tags: Mapped[list[str]] = mapped_column(JSON, default=list)

    cover_path: Mapped[str | None] = mapped_column(String(500))
    source_format: Mapped[str] = mapped_column(String(20), nullable=False)
    source_filename: Mapped[str] = mapped_column(String(300), nullable=False)
    original_path: Mapped[str] = mapped_column(String(1000), nullable=False)
    extracted_path: Mapped[str | None] = mapped_column(String(1000))
    content_hash: Mapped[str] = mapped_column(String(64), nullable=False, unique=True, index=True)
    file_size: Mapped[int] = mapped_column(Integer, default=0)

    status: Mapped[str] = mapped_column(String(20), default="ready", index=True)
    parse_error: Mapped[str | None] = mapped_column(Text)
    metadata_json: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)

    chapter_count: Mapped[int] = mapped_column(Integer, default=0)
    paragraph_count: Mapped[int] = mapped_column(Integer, default=0)
    sentence_count: Mapped[int] = mapped_column(Integer, default=0)
    translated_sentence_count: Mapped[int] = mapped_column(Integer, default=0)
    last_read_at: Mapped[datetime | None] = mapped_column(DateTime())

    chapters: Mapped[list["Chapter"]] = relationship(
        back_populates="book", cascade="all, delete-orphan", passive_deletes=True
    )


class Chapter(IdMixin, Base):
    __tablename__ = "chapters"
    __table_args__ = (
        UniqueConstraint("book_id", "ordinal", name="uq_chapters_book_ordinal"),
        Index("ix_chapters_book_ordinal", "book_id", "ordinal"),
    )

    book_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("books.id", ondelete="CASCADE"), nullable=False, index=True
    )
    ordinal: Mapped[int] = mapped_column(Integer, nullable=False)
    title: Mapped[str] = mapped_column(String(500), nullable=False)
    source_title: Mapped[str | None] = mapped_column(String(500))
    start_offset: Mapped[int] = mapped_column(Integer, default=0)
    end_offset: Mapped[int] = mapped_column(Integer, default=0)
    paragraph_count: Mapped[int] = mapped_column(Integer, default=0)
    sentence_count: Mapped[int] = mapped_column(Integer, default=0)
    translated_count: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(), default=utcnow, onupdate=utcnow)

    book: Mapped[Book] = relationship(back_populates="chapters")
    paragraphs: Mapped[list["Paragraph"]] = relationship(
        back_populates="chapter", cascade="all, delete-orphan", passive_deletes=True
    )


class Paragraph(IdMixin, Base):
    __tablename__ = "paragraphs"
    __table_args__ = (
        UniqueConstraint("chapter_id", "ordinal", name="uq_paragraphs_chapter_ordinal"),
        Index("ix_paragraphs_chapter_ordinal", "chapter_id", "ordinal"),
    )

    book_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("books.id", ondelete="CASCADE"), nullable=False, index=True
    )
    chapter_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("chapters.id", ondelete="CASCADE"), nullable=False, index=True
    )
    ordinal: Mapped[int] = mapped_column(Integer, nullable=False)
    original_text: Mapped[str] = mapped_column(Text, nullable=False)
    normalized_text: Mapped[str] = mapped_column(Text, nullable=False)
    start_offset: Mapped[int] = mapped_column(Integer, default=0)
    end_offset: Mapped[int] = mapped_column(Integer, default=0)
    sentence_count: Mapped[int] = mapped_column(Integer, default=0)

    chapter: Mapped[Chapter] = relationship(back_populates="paragraphs")


class Sentence(IdMixin, Base):
    __tablename__ = "sentences"
    __table_args__ = (
        UniqueConstraint("paragraph_id", "ordinal", name="uq_sentences_paragraph_ordinal"),
        Index("ix_sentences_paragraph_ordinal", "paragraph_id", "ordinal"),
        Index("ix_sentences_book_state", "book_id", "translation_state"),
    )

    book_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("books.id", ondelete="CASCADE"), nullable=False, index=True
    )
    chapter_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("chapters.id", ondelete="CASCADE"), nullable=False, index=True
    )
    paragraph_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("paragraphs.id", ondelete="CASCADE"), nullable=False, index=True
    )
    ordinal: Mapped[int] = mapped_column(Integer, nullable=False)
    original_text: Mapped[str] = mapped_column(Text, nullable=False)
    normalized_text: Mapped[str] = mapped_column(Text, nullable=False)
    start_offset: Mapped[int] = mapped_column(Integer, default=0)
    end_offset: Mapped[int] = mapped_column(Integer, default=0)
    char_count: Mapped[int] = mapped_column(Integer, default=0)
    needs_review: Mapped[bool] = mapped_column(default=False, nullable=False)
    split_confidence: Mapped[float] = mapped_column(Float, default=1.0, nullable=False)

    # pending | queued | translating | completed | failed
    translation_state: Mapped[str] = mapped_column(String(20), default="pending", nullable=False)
    translation_error: Mapped[str | None] = mapped_column(Text)
    translated_at: Mapped[datetime | None] = mapped_column(DateTime())
