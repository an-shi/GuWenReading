"""Multi-device synchronization log and cursors."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from sqlalchemy import JSON, DateTime, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.utils import utcnow
from app.database.base import Base


class SyncOperation(Base):
    __tablename__ = "sync_operations"

    seq: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    device_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    entity_type: Mapped[str] = mapped_column(String(50), nullable=False)
    entity_id: Mapped[str] = mapped_column(String(36), nullable=False)
    operation: Mapped[str] = mapped_column(String(20), nullable=False)
    payload: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)
    base_version: Mapped[int] = mapped_column(Integer, default=0)
    version: Mapped[int] = mapped_column(Integer, default=1)
    client_timestamp: Mapped[datetime | None] = mapped_column(DateTime())
    # applied | conflict | rejected
    status: Mapped[str] = mapped_column(String(20), default="applied", nullable=False)
    conflict: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)
    error: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(), default=utcnow, nullable=False)


class SyncCursor(Base):
    __tablename__ = "sync_cursor"

    device_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    last_seq: Mapped[int] = mapped_column(Integer, default=0)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(), default=utcnow, onupdate=utcnow, nullable=False
    )
