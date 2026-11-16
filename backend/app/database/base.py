"""SQLAlchemy declarative base and shared columns."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from sqlalchemy import DateTime, Integer, MetaData, String
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

from app.core.utils import new_id, utcnow

NAMING_CONVENTION = {
    "ix": "ix_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=NAMING_CONVENTION)

    def as_dict(self) -> dict[str, Any]:
        return {column.name: getattr(self, column.name) for column in self.__table__.columns}


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(DateTime(), default=utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(), default=utcnow, onupdate=utcnow, nullable=False
    )


class SyncMixin(TimestampMixin):
    """Fields required by optional multi-device synchronization."""

    version: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(), nullable=True)


class IdMixin:
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
