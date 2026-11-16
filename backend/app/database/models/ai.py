"""AI configuration, prompts, translation records, cache and tasks."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from sqlalchemy import (
    JSON, DateTime, Float, ForeignKey, Index, Integer, String, Text, UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.core.utils import utcnow
from app.database.base import Base, IdMixin, SyncMixin, TimestampMixin


class AIProvider(IdMixin, SyncMixin, Base):
    __tablename__ = "ai_providers"

    name: Mapped[str] = mapped_column(String(100), nullable=False)
    kind: Mapped[str] = mapped_column(String(40), default="openai_compatible", nullable=False)
    base_url: Mapped[str] = mapped_column(String(500), nullable=False)
    api_key_encrypted: Mapped[str | None] = mapped_column(Text)
    api_key_hint: Mapped[str | None] = mapped_column(String(20))
    headers: Mapped[dict[str, str]] = mapped_column(JSON, default=dict)
    enabled: Mapped[bool] = mapped_column(default=True, nullable=False)
    notes: Mapped[str | None] = mapped_column(Text)


class AIModel(IdMixin, SyncMixin, Base):
    __tablename__ = "ai_models"
    __table_args__ = (UniqueConstraint("provider_id", "name", name="uq_ai_models_provider_name"),)

    provider_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("ai_providers.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    display_name: Mapped[str] = mapped_column(String(200), nullable=False)
    context_window: Mapped[int] = mapped_column(Integer, default=8192)
    max_output_tokens: Mapped[int] = mapped_column(Integer, default=2048)
    timeout_seconds: Mapped[int] = mapped_column(Integer, default=120)
    max_concurrency: Mapped[int] = mapped_column(Integer, default=2)
    supports_streaming: Mapped[bool] = mapped_column(default=False)
    supports_json: Mapped[bool] = mapped_column(default=True)
    capabilities: Mapped[list[str]] = mapped_column(JSON, default=lambda: ["translation", "chat"])
    params: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)
    enabled: Mapped[bool] = mapped_column(default=True, nullable=False)
    is_default_translation: Mapped[bool] = mapped_column(default=False)
    is_default_chat: Mapped[bool] = mapped_column(default=False)


class PromptTemplate(IdMixin, Base):
    __tablename__ = "prompt_templates"
    __table_args__ = (UniqueConstraint("key", "version", name="uq_prompt_key_version"),)

    key: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
    version: Mapped[int] = mapped_column(Integer, nullable=False)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    template: Mapped[str] = mapped_column(Text, nullable=False)
    variables: Mapped[list[str]] = mapped_column(JSON, default=list)
    is_active: Mapped[bool] = mapped_column(default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(), default=utcnow, nullable=False)


class Translation(IdMixin, SyncMixin, Base):
    __tablename__ = "translations"
    __table_args__ = (
        UniqueConstraint("sentence_id", name="uq_translations_sentence"),
        Index("ix_translations_chapter", "chapter_id"),
    )

    sentence_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("sentences.id", ondelete="CASCADE"), nullable=False
    )
    paragraph_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("paragraphs.id", ondelete="CASCADE"), nullable=False
    )
    chapter_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("chapters.id", ondelete="CASCADE"), nullable=False
    )
    book_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("books.id", ondelete="CASCADE"), nullable=False
    )
    text: Mapped[str] = mapped_column(Text, nullable=False)
    origin: Mapped[str] = mapped_column(String(20), default="ai", nullable=False)
    status: Mapped[str] = mapped_column(String(30), default="completed", nullable=False)
    model_name: Mapped[str | None] = mapped_column(String(200))
    provider_name: Mapped[str | None] = mapped_column(String(100))
    prompt_version: Mapped[int | None] = mapped_column(Integer)
    source_hash: Mapped[str | None] = mapped_column(String(64))
    context_hash: Mapped[str | None] = mapped_column(String(64))
    cache_key: Mapped[str | None] = mapped_column(String(120))
    confidence: Mapped[float | None] = mapped_column(Float)
    edited_at: Mapped[datetime | None] = mapped_column(DateTime())


class TranslationVersion(IdMixin, Base):
    __tablename__ = "translation_versions"
    __table_args__ = (Index("ix_translation_versions_sentence", "sentence_id", "created_at"),)

    translation_id: Mapped[str | None] = mapped_column(String(36))
    sentence_id: Mapped[str] = mapped_column(String(36), nullable=False)
    text: Mapped[str] = mapped_column(Text, nullable=False)
    origin: Mapped[str] = mapped_column(String(20), nullable=False)
    model_name: Mapped[str | None] = mapped_column(String(200))
    prompt_version: Mapped[int | None] = mapped_column(Integer)
    note: Mapped[str | None] = mapped_column(String(300))
    created_at: Mapped[datetime] = mapped_column(DateTime(), default=utcnow, nullable=False)


class TranslationReview(IdMixin, Base):
    __tablename__ = "translation_reviews"
    __table_args__ = (Index("ix_translation_reviews_status", "status"),)

    translation_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("translations.id", ondelete="CASCADE"), nullable=False
    )
    sentence_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("sentences.id", ondelete="CASCADE"), nullable=False
    )
    candidate_text: Mapped[str] = mapped_column(Text, nullable=False)
    previous_text: Mapped[str] = mapped_column(Text, nullable=False)
    reason: Mapped[str] = mapped_column(String(50), default="manual_conflict")
    status: Mapped[str] = mapped_column(String(20), default="pending", nullable=False)
    model_name: Mapped[str | None] = mapped_column(String(200))
    prompt_version: Mapped[int | None] = mapped_column(Integer)
    cache_key: Mapped[str | None] = mapped_column(String(120))
    created_at: Mapped[datetime] = mapped_column(DateTime(), default=utcnow, nullable=False)
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime())


class TranslationCache(Base):
    __tablename__ = "translation_cache"

    cache_key: Mapped[str] = mapped_column(String(120), primary_key=True)
    source_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    context_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    model_key: Mapped[str] = mapped_column(String(200), nullable=False)
    prompt_version: Mapped[int] = mapped_column(Integer, nullable=False)
    params_json: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)
    translated_text: Mapped[str] = mapped_column(Text, nullable=False)
    hit_count: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(), default=utcnow, nullable=False)
    last_used_at: Mapped[datetime] = mapped_column(DateTime(), default=utcnow, nullable=False)


class Task(IdMixin, Base):
    __tablename__ = "tasks"
    __table_args__ = (Index("ix_tasks_status_created", "status", "created_at"),)

    type: Mapped[str] = mapped_column(String(60), nullable=False, index=True)
    status: Mapped[str] = mapped_column(String(20), default="queued", nullable=False)
    title: Mapped[str] = mapped_column(String(300), nullable=False)
    progress: Mapped[float] = mapped_column(Float, default=0.0)
    total: Mapped[int] = mapped_column(Integer, default=0)
    completed: Mapped[int] = mapped_column(Integer, default=0)
    failed_count: Mapped[int] = mapped_column(Integer, default=0)
    payload: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)
    result: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)
    error: Mapped[str | None] = mapped_column(Text)
    cancel_requested: Mapped[bool] = mapped_column(default=False, nullable=False)
    book_id: Mapped[str | None] = mapped_column(String(36), index=True)
    chapter_id: Mapped[str | None] = mapped_column(String(36), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(), default=utcnow, nullable=False)
    started_at: Mapped[datetime | None] = mapped_column(DateTime())
    finished_at: Mapped[datetime | None] = mapped_column(DateTime())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(), default=utcnow, onupdate=utcnow, nullable=False
    )


class AssistantSession(IdMixin, Base):
    __tablename__ = "assistant_sessions"

    title: Mapped[str] = mapped_column(String(300), default="AI 阅读助手")
    book_id: Mapped[str | None] = mapped_column(String(36), index=True)
    chapter_id: Mapped[str | None] = mapped_column(String(36), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(), default=utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(), default=utcnow, onupdate=utcnow, nullable=False
    )


class AssistantMessage(IdMixin, Base):
    __tablename__ = "assistant_messages"
    __table_args__ = (Index("ix_assistant_messages_session", "session_id", "created_at"),)

    session_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("assistant_sessions.id", ondelete="CASCADE"), nullable=False
    )
    role: Mapped[str] = mapped_column(String(20), nullable=False)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    citations: Mapped[list[dict[str, Any]]] = mapped_column(JSON, default=list)
    model_name: Mapped[str | None] = mapped_column(String(200))
    created_at: Mapped[datetime] = mapped_column(DateTime(), default=utcnow, nullable=False)


class Glossary(IdMixin, TimestampMixin, Base):
    __tablename__ = "glossary"

    term: Mapped[str] = mapped_column(String(200), nullable=False, index=True)
    reading: Mapped[str | None] = mapped_column(String(200))
    definition: Mapped[str] = mapped_column(Text, nullable=False)
    category: Mapped[str | None] = mapped_column(String(100), index=True)
    aliases: Mapped[list[str]] = mapped_column(JSON, default=list)
    source: Mapped[str | None] = mapped_column(String(300))
