"""Async engine/session factory and SQLite bootstrap."""

from __future__ import annotations

from sqlalchemy import event, text
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import Settings
from app.database.base import Base
from app.database import models as _models  # noqa: F401  (register metadata)


def make_engine(settings: Settings) -> AsyncEngine:
    url = settings.database_url or ""
    kwargs: dict = {"pool_pre_ping": True}
    if url.startswith("sqlite"):
        kwargs["connect_args"] = {"timeout": 30, "check_same_thread": False}
    engine = create_async_engine(url, **kwargs)

    if url.startswith("sqlite"):
        @event.listens_for(engine.sync_engine, "connect")
        def _sqlite_pragmas(dbapi_connection, _record):  # pragma: no cover - driver hook
            cursor = dbapi_connection.cursor()
            cursor.execute("PRAGMA foreign_keys=ON")
            cursor.execute("PRAGMA busy_timeout=30000")
            try:
                cursor.execute("PRAGMA journal_mode=WAL")
            except Exception:
                pass
            cursor.close()

    return engine


def make_session_factory(engine: AsyncEngine) -> async_sessionmaker[AsyncSession]:
    return async_sessionmaker(engine, expire_on_commit=False, autoflush=False)


async def _ensure_fts5(engine: AsyncEngine) -> bool:
    from app.database.fts import ensure_fts

    return await ensure_fts(engine)


async def create_schema(engine: AsyncEngine) -> bool:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    return await _ensure_fts5(engine)


async def drop_schema(engine: AsyncEngine) -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)


async def check_database(engine: AsyncEngine) -> bool:
    async with engine.connect() as conn:
        await conn.execute(text("SELECT 1"))
    return True
