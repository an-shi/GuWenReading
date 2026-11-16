"""Cross-book historical knowledge graph and timeline entities.

Every AI-extracted assertion keeps its evidence and an explicit review status.
Nothing inferred by AI is silently promoted to confirmed fact.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from sqlalchemy import (
    JSON, DateTime, Float, ForeignKey, Index, Integer, String, Text, UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.core.utils import utcnow
from app.database.base import Base, IdMixin, SyncMixin


class HistoricalEntity(IdMixin, SyncMixin, Base):
    __tablename__ = "historical_entities"
    __table_args__ = (Index("ix_entities_name", "canonical_name"),)

    canonical_name: Mapped[str] = mapped_column(String(200), nullable=False)
    kind: Mapped[str] = mapped_column(String(30), default="person", nullable=False, index=True)
    dynasty: Mapped[str | None] = mapped_column(String(100), index=True)
    courtesy_name: Mapped[str | None] = mapped_column(String(100))
    art_name: Mapped[str | None] = mapped_column(String(100))
    posthumous_name: Mapped[str | None] = mapped_column(String(100))
    temple_name: Mapped[str | None] = mapped_column(String(100))
    aliases: Mapped[list[str]] = mapped_column(JSON, default=list)
    birth_raw: Mapped[str | None] = mapped_column(String(100))
    death_raw: Mapped[str | None] = mapped_column(String(100))
    birth_year: Mapped[int | None] = mapped_column(Integer)
    death_year: Mapped[int | None] = mapped_column(Integer)
    identity: Mapped[str | None] = mapped_column(String(200))
    offices: Mapped[list[str]] = mapped_column(JSON, default=list)
    summary: Mapped[str | None] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(20), default="pending", nullable=False)
    confidence: Mapped[float | None] = mapped_column(Float)


class EntityMention(IdMixin, SyncMixin, Base):
    __tablename__ = "entity_mentions"
    __table_args__ = (Index("ix_mentions_sentence", "sentence_id"),)

    entity_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("historical_entities.id", ondelete="SET NULL"), index=True
    )
    book_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("books.id", ondelete="CASCADE"), nullable=False, index=True
    )
    chapter_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("chapters.id", ondelete="CASCADE"), nullable=False
    )
    paragraph_id: Mapped[str | None] = mapped_column(String(36))
    sentence_id: Mapped[str | None] = mapped_column(String(36))
    surface_text: Mapped[str] = mapped_column(String(200), nullable=False)
    start_offset: Mapped[int | None] = mapped_column(Integer)
    end_offset: Mapped[int | None] = mapped_column(Integer)
    source: Mapped[str] = mapped_column(String(20), default="ai", nullable=False)
    confidence: Mapped[float | None] = mapped_column(Float)
    status: Mapped[str] = mapped_column(String(20), default="pending", nullable=False)


class EntityRelation(IdMixin, SyncMixin, Base):
    __tablename__ = "entity_relations"

    source_entity_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("historical_entities.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    target_entity_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("historical_entities.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    relation_type: Mapped[str] = mapped_column(String(50), nullable=False, index=True)
    label: Mapped[str | None] = mapped_column(String(100))
    description: Mapped[str | None] = mapped_column(Text)
    # explicit | inferred | confirmed | rejected
    status: Mapped[str] = mapped_column(String(20), default="inferred", nullable=False)
    confidence: Mapped[float | None] = mapped_column(Float)
    source: Mapped[str] = mapped_column(String(20), default="ai", nullable=False)


class RelationSource(IdMixin, Base):
    __tablename__ = "relation_sources"

    relation_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("entity_relations.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    book_id: Mapped[str | None] = mapped_column(String(36))
    chapter_id: Mapped[str | None] = mapped_column(String(36))
    paragraph_id: Mapped[str | None] = mapped_column(String(36))
    sentence_id: Mapped[str | None] = mapped_column(String(36))
    quote: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(), default=utcnow, nullable=False)


class HistoricalEvent(IdMixin, SyncMixin, Base):
    __tablename__ = "historical_events"
    __table_args__ = (Index("ix_events_time", "time_start_year", "time_end_year"),)

    name: Mapped[str] = mapped_column(String(300), nullable=False, index=True)
    event_type: Mapped[str] = mapped_column(String(40), default="other", nullable=False, index=True)
    description: Mapped[str | None] = mapped_column(Text)
    dynasty: Mapped[str | None] = mapped_column(String(100), index=True)

    # Original chronology is always preserved verbatim.
    time_raw: Mapped[str | None] = mapped_column(String(200))
    era_name: Mapped[str | None] = mapped_column(String(100))
    reign_year: Mapped[str | None] = mapped_column(String(100))
    ganzhi: Mapped[str | None] = mapped_column(String(20))
    time_start_year: Mapped[int | None] = mapped_column(Integer)
    time_end_year: Mapped[int | None] = mapped_column(Integer)
    # exact | day | month | year | range | circa | unknown
    time_precision: Mapped[str] = mapped_column(String(20), default="unknown")
    time_note: Mapped[str | None] = mapped_column(Text)
    confidence: Mapped[float | None] = mapped_column(Float)
    # extracted | confirmed | rejected
    status: Mapped[str] = mapped_column(String(20), default="extracted", nullable=False)
    tags: Mapped[list[str]] = mapped_column(JSON, default=list)
    metadata_json: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)


class EventParticipant(IdMixin, Base):
    __tablename__ = "event_participants"
    __table_args__ = (UniqueConstraint("event_id", "entity_id", "role", name="uq_event_participant"),)

    event_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("historical_events.id", ondelete="CASCADE"), nullable=False
    )
    entity_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("historical_entities.id", ondelete="CASCADE"), nullable=False
    )
    role: Mapped[str | None] = mapped_column(String(100))


class EventSource(IdMixin, Base):
    __tablename__ = "event_sources"

    event_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("historical_events.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    book_id: Mapped[str | None] = mapped_column(String(36))
    chapter_id: Mapped[str | None] = mapped_column(String(36))
    paragraph_id: Mapped[str | None] = mapped_column(String(36))
    sentence_id: Mapped[str | None] = mapped_column(String(36))
    quote: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(), default=utcnow, nullable=False)
