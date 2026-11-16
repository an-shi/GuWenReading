"""Reading state, annotations, bookmarks, devices and users."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import JSON, DateTime, Float, ForeignKey, Index, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.utils import utcnow
from app.database.base import Base, IdMixin, SyncMixin


class Annotation(IdMixin, SyncMixin, Base):
    __tablename__ = "annotations"
    __table_args__ = (Index("ix_annotations_book", "book_id", "chapter_id"),)

    book_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("books.id", ondelete="CASCADE"), nullable=False
    )
    chapter_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("chapters.id", ondelete="CASCADE")
    )
    paragraph_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("paragraphs.id", ondelete="CASCADE")
    )
    sentence_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("sentences.id", ondelete="CASCADE")
    )
    quote: Mapped[str | None] = mapped_column(Text)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    color: Mapped[str] = mapped_column(String(20), default="amber")
    tags: Mapped[list[str]] = mapped_column(JSON, default=list)
    device_id: Mapped[str | None] = mapped_column(String(36), index=True)


class Bookmark(IdMixin, SyncMixin, Base):
    __tablename__ = "bookmarks"
    __table_args__ = (Index("ix_bookmarks_book", "book_id", "chapter_id"),)

    book_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("books.id", ondelete="CASCADE"), nullable=False
    )
    chapter_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("chapters.id", ondelete="CASCADE"), nullable=False
    )
    paragraph_id: Mapped[str | None] = mapped_column(String(36))
    sentence_id: Mapped[str | None] = mapped_column(String(36))
    label: Mapped[str | None] = mapped_column(String(300))
    position_ratio: Mapped[float] = mapped_column(Float, default=0.0)
    device_id: Mapped[str | None] = mapped_column(String(36), index=True)


class ReadingProgress(IdMixin, SyncMixin, Base):
    """Progress is deliberately per-device; devices never overwrite each other."""

    __tablename__ = "reading_progress"
    __table_args__ = (UniqueConstraint("book_id", "device_id", name="uq_progress_book_device"),)

    book_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("books.id", ondelete="CASCADE"), nullable=False, index=True
    )
    device_id: Mapped[str] = mapped_column(String(36), nullable=False, default="local")
    chapter_id: Mapped[str | None] = mapped_column(String(36))
    paragraph_id: Mapped[str | None] = mapped_column(String(36))
    sentence_id: Mapped[str | None] = mapped_column(String(36))
    position_ratio: Mapped[float] = mapped_column(Float, default=0.0)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(), default=utcnow, onupdate=utcnow, nullable=False
    )


class Device(IdMixin, SyncMixin, Base):
    __tablename__ = "devices"

    name: Mapped[str] = mapped_column(String(200), nullable=False)
    platform: Mapped[str] = mapped_column(String(40), nullable=False)
    fingerprint: Mapped[str | None] = mapped_column(String(200), unique=True)
    app_version: Mapped[str | None] = mapped_column(String(40))
    user_id: Mapped[str | None] = mapped_column(String(36), ForeignKey("users.id", ondelete="SET NULL"))
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime())
    is_current: Mapped[bool] = mapped_column(default=False)


class User(IdMixin, Base):
    __tablename__ = "users"

    username: Mapped[str] = mapped_column(String(100), nullable=False, unique=True)
    display_name: Mapped[str | None] = mapped_column(String(200))
    password_hash: Mapped[str] = mapped_column(String(300), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(), default=utcnow, nullable=False)
