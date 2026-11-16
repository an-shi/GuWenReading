"""Incremental multi-device synchronization.

Supported payloads: book metadata, manual/AI translations, annotations, bookmarks,
per-device reading progress, entities, relations and events. Book/chapter content
is transferred through the manifest and chapter download endpoints rather than
the operation log.

Conflict rules:
* a local manual translation is never overwritten by an AI translation;
* concurrent manual translations with stale base versions are reported as
  conflicts instead of silently overwriting;
* other records use last-write-wins with explicit version checks, and conflicts
  are recorded for review.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.errors import AppError, ErrorCode
from app.core.utils import iso, new_id, utcnow
from app.database.fts import index_sentence
from app.database.models import (
    Annotation, Book, Bookmark, Chapter, EntityRelation, EventParticipant, EventSource,
    HistoricalEntity, HistoricalEvent, ReadingProgress, RelationSource, Sentence,
    SyncCursor, SyncOperation, Translation, TranslationVersion,
)
from app.modules.book_manager.queries import get_book
from app.modules.knowledge.chronology import parse_time

SUPPORTED_TYPES = {
    "book", "translation", "annotation", "bookmark", "reading_progress",
    "entity", "relation", "event",
}


def _parse_dt(value: Any) -> datetime | None:
    if not value:
        return None
    if isinstance(value, datetime):
        return value.replace(tzinfo=None)
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        return parsed.replace(tzinfo=None)
    except ValueError:
        return None


def _dt(value: datetime | None) -> str | None:
    return iso(value)


def _normalize_entity(entity: str) -> dict[str, Any]:
    return {
        "id": entity.id,
        "version": entity.version,
        "updated_at": _dt(entity.updated_at),
        "deleted_at": _dt(entity.deleted_at),
    }


def _conflict(reason: str, server: dict[str, Any] | None = None) -> dict[str, Any]:
    return {"reason": reason, "server": server or {}}


class SyncService:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    def ensure_enabled(self) -> None:
        if not (self.settings.sync_enabled or self.settings.mode == "server"):
            raise AppError(
                ErrorCode.SYNC_DISABLED,
                "Synchronization is disabled. Enable it and configure a server to use multi-device sync.",
                status_code=409,
            )

    async def _ensure_device(self, session: AsyncSession, device_id: str) -> None:
        from app.database.models import Device

        device = await session.get(Device, device_id)
        if device is None:
            existing = await session.scalar(
                select(Device).where(Device.fingerprint == device_id)
            )
            if existing is None:
                session.add(Device(
                    id=device_id, name="Synced device", platform="other",
                    fingerprint=device_id, last_seen_at=utcnow(),
                ))
            else:
                existing.last_seen_at = utcnow()
        else:
            device.last_seen_at = utcnow()
            device.deleted_at = None

    async def push(
        self, session: AsyncSession, device_id: str, operations: list[Any]
    ) -> dict[str, Any]:
        self.ensure_enabled()
        await self._ensure_device(session, device_id)
        results: list[dict[str, Any]] = []
        conflicts = 0
        for operation in operations:
            entity_type = operation.entity_type
            if entity_type not in SUPPORTED_TYPES:
                results.append({
                    "entity_type": entity_type, "entity_id": operation.entity_id,
                    "status": "rejected", "error": f"Unsupported entity type: {entity_type}",
                })
                continue
            handler = getattr(self, f"_apply_{entity_type}", None)
            assert handler is not None
            try:
                outcome = await handler(
                    session, operation.entity_id, operation.operation,
                    operation.data, operation.base_version, operation.version,
                    operation.updated_at, device_id,
                )
            except AppError as exc:
                outcome = {"status": "rejected", "error": exc.message}
            except Exception as exc:
                outcome = {"status": "rejected", "error": str(exc)[:500]}

            payload: dict[str, Any] = dict(operation.data or {})
            if outcome["status"] == "applied":
                payload.update(outcome.get("data") or {})
            record = SyncOperation(
                device_id=device_id,
                entity_type=entity_type,
                entity_id=outcome.get("entity_id", operation.entity_id),
                operation=operation.operation,
                payload=payload,
                base_version=operation.base_version,
                version=outcome.get("version", operation.version),
                client_timestamp=_parse_dt(operation.updated_at),
                status=outcome["status"],
                conflict=outcome.get("conflict") or {},
                error=outcome.get("error"),
            )
            session.add(record)
            await session.flush()
            if outcome["status"] == "conflict":
                conflicts += 1
            results.append({
                "entity_type": entity_type,
                "entity_id": record.entity_id,
                "status": record.status,
                "seq": record.seq,
                "version": record.version,
                "error": record.error,
            })
        await session.commit()
        return {"results": results, "conflicts": conflicts}

    async def pull(
        self, session: AsyncSession, device_id: str, after: int = 0, limit: int = 200
    ) -> dict[str, Any]:
        self.ensure_enabled()
        rows = list((await session.scalars(
            select(SyncOperation)
            .where(
                SyncOperation.seq > after,
                SyncOperation.status == "applied",
            )
            .order_by(SyncOperation.seq)
            .limit(limit)
        )).all())
        cursor = await session.get(SyncCursor, device_id)
        if cursor is None:
            cursor = SyncCursor(device_id=device_id, last_seq=after)
            session.add(cursor)
        if rows:
            cursor.last_seq = max(cursor.last_seq, rows[-1].seq)
        cursor.updated_at = utcnow()
        await session.commit()
        return {
            "operations": [
                {
                    "seq": row.seq,
                    "entity_type": row.entity_type,
                    "entity_id": row.entity_id,
                    "operation": row.operation,
                    "version": row.version,
                    "data": row.payload,
                    "created_at": iso(row.created_at),
                }
                for row in rows
            ],
            "next_cursor": cursor.last_seq,
            "has_more": len(rows) == limit,
        }

    async def status(self, session: AsyncSession, device_id: str) -> dict[str, Any]:
        self.ensure_enabled()
        cursor = await session.get(SyncCursor, device_id)
        conflicts = await session.scalar(
            select(func.count()).select_from(SyncOperation).where(
                SyncOperation.status == "conflict"
            )
        ) or 0
        latest = await session.scalar(select(func.max(SyncOperation.seq))) or 0
        return {
            "enabled": True,
            "device_id": device_id,
            "last_pulled_seq": cursor.last_seq if cursor else 0,
            "latest_seq": latest,
            "pending_conflicts": conflicts,
            "supported_entity_types": sorted(SUPPORTED_TYPES),
        }

    async def conflicts(self, session: AsyncSession, limit: int = 100) -> list[dict[str, Any]]:
        self.ensure_enabled()
        rows = list((await session.scalars(
            select(SyncOperation)
            .where(SyncOperation.status == "conflict")
            .order_by(SyncOperation.seq.desc())
            .limit(limit)
        )).all())
        return [
            {
                "seq": row.seq,
                "device_id": row.device_id,
                "entity_type": row.entity_type,
                "entity_id": row.entity_id,
                "operation": row.operation,
                "base_version": row.base_version,
                "version": row.version,
                "payload": row.payload,
                "conflict": row.conflict,
                "created_at": iso(row.created_at),
            }
            for row in rows
        ]

    async def resolve_conflict(
        self, session: AsyncSession, seq: int, action: str
    ) -> dict[str, Any]:
        self.ensure_enabled()
        record = await session.get(SyncOperation, seq)
        if record is None or record.status != "conflict":
            raise AppError(ErrorCode.NOT_FOUND, "Sync conflict not found", status_code=404)
        if action == "accept_server":
            record.status = "resolved_server"
            record.conflict = {**record.conflict, "resolved": "server"}
            await session.commit()
            return {"seq": seq, "status": record.status}
        if action != "accept_client":
            raise AppError(ErrorCode.VALIDATION_ERROR, "action must be accept_client or accept_server", status_code=422)
        handler = getattr(self, f"_apply_{record.entity_type}", None)
        if handler is None:
            raise AppError(ErrorCode.VALIDATION_ERROR, "Unsupported conflict entity type", status_code=422)
        outcome = await handler(
            session, record.entity_id, record.operation, record.payload,
            0, record.version, None, record.device_id, force=True,
        )
        await session.flush()
        record.status = "applied" if outcome["status"] == "applied" else "conflict"
        record.conflict = {**record.conflict, "resolved": "client", "result": outcome}
        record.version = outcome.get("version", record.version)
        if outcome["status"] == "applied":
            record.payload = {**record.payload, **(outcome.get("data") or {})}
        await session.commit()
        return {"seq": seq, "status": record.status}

    # --------------------------------------------------------------- handlers
    async def _apply_book(
        self, session, entity_id, operation, data, base_version, version,
        updated_at, device_id, force=False,
    ) -> dict[str, Any]:
        book = await get_book(session, entity_id, include_deleted=True)
        if operation == "delete":
            book.deleted_at = utcnow()
            book.version += 1
            await session.flush()
            return {"status": "applied", "data": _normalize_entity(book), "version": book.version}
        if not force and base_version < book.version and book.deleted_at is not None:
            return {"status": "conflict", "conflict": _conflict("book deleted on server", _normalize_entity(book))}
        for key in ("title", "author", "dynasty", "category", "description", "tags"):
            if key in data and data[key] is not None:
                setattr(book, key, data[key])
        book.deleted_at = None
        book.version = max(book.version + 1, version or 1)
        await session.flush()
        return {"status": "applied", "data": _normalize_entity(book), "version": book.version}

    async def _apply_translation(
        self, session, entity_id, operation, data, base_version, version,
        updated_at, device_id, force=False,
    ) -> dict[str, Any]:
        sentence_id = data.get("sentence_id")
        if not sentence_id:
            return {"status": "rejected", "error": "translation requires sentence_id"}
        sentence = await session.get(Sentence, sentence_id)
        if sentence is None:
            return {"status": "rejected", "error": "sentence does not exist on this server"}
        existing = await session.scalar(
            select(Translation).where(Translation.sentence_id == sentence_id)
        )
        if operation == "delete":
            if existing is None:
                return {"status": "applied", "data": {"sentence_id": sentence_id, "deleted": True}}
            existing.deleted_at = utcnow()
            existing.version += 1
            await session.flush()
            return {"status": "applied", "data": _normalize_entity(existing), "version": existing.version}
        if existing is not None and not force:
            incoming_manual = data.get("origin") == "manual"
            if existing.deleted_at is None and existing.origin == "manual" and not incoming_manual:
                if data.get("text") != existing.text:
                    return {
                        "status": "conflict",
                        "conflict": _conflict("manual translation is protected", _normalize_entity(existing)),
                        "data": _normalize_entity(existing),
                    }
            if (
                existing.deleted_at is None and incoming_manual and existing.origin == "manual"
                and data.get("text") != existing.text and base_version < existing.version
            ):
                return {
                    "status": "conflict",
                    "conflict": _conflict("concurrent manual edits", _normalize_entity(existing)),
                    "data": _normalize_entity(existing),
                }
        if existing is None:
            existing = Translation(
                id=entity_id,
                sentence_id=sentence_id,
                paragraph_id=sentence.paragraph_id,
                chapter_id=sentence.chapter_id,
                book_id=sentence.book_id,
                text=str(data.get("text") or "").strip(),
                origin=str(data.get("origin") or "manual"),
                status="completed",
                model_name=data.get("model_name"),
                prompt_version=data.get("prompt_version"),
                edited_at=_parse_dt(data.get("edited_at")),
            )
            session.add(existing)
        else:
            if existing.text != str(data.get("text") or "").strip():
                session.add(TranslationVersion(
                    translation_id=existing.id,
                    sentence_id=sentence_id,
                    text=existing.text,
                    origin=existing.origin,
                    note="replaced by sync from another device",
                ))
            existing.text = str(data.get("text") or existing.text).strip()
            existing.origin = str(data.get("origin") or existing.origin)
            existing.model_name = data.get("model_name") or existing.model_name
            existing.prompt_version = data.get("prompt_version") or existing.prompt_version
            existing.deleted_at = None
            existing.version = max(existing.version + 1, version or 1)
        sentence.translation_state = "completed"
        await session.flush()
        chapter_row = await session.get(Chapter, sentence.chapter_id)
        book_row = await session.get(Book, sentence.book_id)
        if chapter_row is not None and book_row is not None:
            await index_sentence(
                session,
                sentence_id=sentence.id,
                book_id=sentence.book_id,
                chapter_id=sentence.chapter_id,
                title=f"{book_row.title} · {chapter_row.title}",
                original_text=sentence.original_text,
                translated_text=existing.text,
            )
        return {"status": "applied", "data": _normalize_entity(existing), "version": existing.version}

    async def _apply_annotation(
        self, session, entity_id, operation, data, base_version, version,
        updated_at, device_id, force=False,
    ) -> dict[str, Any]:
        row = await session.get(Annotation, entity_id)
        if operation == "delete":
            if row is None:
                return {"status": "applied", "data": {"id": entity_id, "deleted": True}}
            row.deleted_at = utcnow()
            row.version += 1
            await session.flush()
            return {"status": "applied", "data": _normalize_entity(row), "version": row.version}
        if row is None:
            book = await session.get(Book, data.get("book_id"))
            if book is None or book.deleted_at is not None:
                return {"status": "rejected", "error": "annotation book does not exist on this server"}
            row = Annotation(
                id=entity_id,
                book_id=book.id,
                chapter_id=data.get("chapter_id"),
                paragraph_id=data.get("paragraph_id"),
                sentence_id=data.get("sentence_id"),
                quote=data.get("quote"),
                content=str(data.get("content") or "").strip(),
                color=str(data.get("color") or "amber"),
                tags=data.get("tags") or [],
                device_id=device_id,
            )
            session.add(row)
        else:
            if not force and base_version < row.version and (
                not updated_at or (_parse_dt(updated_at) or datetime.min) < row.updated_at
            ):
                return {"status": "conflict", "conflict": _conflict("annotation changed on server", _normalize_entity(row))}
            for key in ("quote", "content", "color", "tags"):
                if key in data and data[key] is not None:
                    setattr(row, key, data[key])
            row.deleted_at = None
            row.version = max(row.version + 1, version or 1)
        await session.flush()
        return {"status": "applied", "data": _normalize_entity(row), "version": row.version}

    async def _apply_bookmark(
        self, session, entity_id, operation, data, base_version, version,
        updated_at, device_id, force=False,
    ) -> dict[str, Any]:
        row = await session.get(Bookmark, entity_id)
        if operation == "delete":
            if row is None:
                return {"status": "applied", "data": {"id": entity_id, "deleted": True}}
            row.deleted_at = utcnow()
            row.version += 1
            await session.flush()
            return {"status": "applied", "data": _normalize_entity(row), "version": row.version}
        if row is None:
            book = await session.get(Book, data.get("book_id"))
            if book is None or book.deleted_at is not None:
                return {"status": "rejected", "error": "bookmark book does not exist on this server"}
            if not data.get("chapter_id"):
                return {"status": "rejected", "error": "bookmark chapter_id is required"}
            row = Bookmark(
                id=entity_id,
                book_id=book.id,
                chapter_id=data.get("chapter_id"),
                paragraph_id=data.get("paragraph_id"),
                sentence_id=data.get("sentence_id"),
                label=data.get("label"),
                position_ratio=float(data.get("position_ratio") or 0),
                device_id=device_id,
            )
            session.add(row)
        else:
            if not force and base_version < row.version and (
                not updated_at or (_parse_dt(updated_at) or datetime.min) < row.updated_at
            ):
                return {"status": "conflict", "conflict": _conflict("bookmark changed on server", _normalize_entity(row))}
            for key in ("label", "position_ratio", "paragraph_id", "sentence_id"):
                if key in data and data[key] is not None:
                    setattr(row, key, data[key])
            row.deleted_at = None
            row.version = max(row.version + 1, version or 1)
        await session.flush()
        return {"status": "applied", "data": _normalize_entity(row), "version": row.version}

    async def _apply_reading_progress(
        self, session, entity_id, operation, data, base_version, version,
        updated_at, device_id, force=False,
    ) -> dict[str, Any]:
        book_id = data.get("book_id")
        row = await session.scalar(
            select(ReadingProgress).where(
                ReadingProgress.book_id == book_id,
                ReadingProgress.device_id == (data.get("device_id") or device_id),
            )
        )
        if row is None:
            row = await session.get(ReadingProgress, entity_id)
        if operation == "delete":
            if row is not None:
                row.deleted_at = utcnow()
                row.version += 1
                await session.flush()
            return {"status": "applied", "data": {"id": entity_id, "deleted": True}}
        book = await session.get(Book, book_id)
        if book is None or book.deleted_at is not None:
            return {"status": "rejected", "error": "book does not exist on this server"}
        if row is None:
            row = ReadingProgress(
                id=entity_id,
                book_id=book_id,
                device_id=data.get("device_id") or device_id,
                chapter_id=data.get("chapter_id"),
                paragraph_id=data.get("paragraph_id"),
                sentence_id=data.get("sentence_id"),
                position_ratio=float(data.get("position_ratio") or 0),
            )
            session.add(row)
        else:
            row.chapter_id = data.get("chapter_id") or row.chapter_id
            row.paragraph_id = data.get("paragraph_id") or row.paragraph_id
            row.sentence_id = data.get("sentence_id") or row.sentence_id
            row.position_ratio = float(data.get("position_ratio") or 0)
            row.deleted_at = None
            row.version += 1
        book.last_read_at = utcnow()
        await session.flush()
        return {"status": "applied", "data": _normalize_entity(row), "version": row.version}

    async def _apply_entity(
        self, session, entity_id, operation, data, base_version, version,
        updated_at, device_id, force=False,
    ) -> dict[str, Any]:
        row = await session.get(HistoricalEntity, entity_id)
        if operation == "delete":
            if row is None:
                return {"status": "applied", "data": {"id": entity_id, "deleted": True}}
            row.deleted_at = utcnow()
            row.version += 1
            await session.flush()
            return {"status": "applied", "data": _normalize_entity(row), "version": row.version}
        if row is None:
            name = str(data.get("canonical_name") or "").strip()
            if not name:
                return {"status": "rejected", "error": "entity canonical_name is required"}
            row = HistoricalEntity(
                id=entity_id,
                canonical_name=name[:200],
                kind=str(data.get("kind") or "person"),
                dynasty=data.get("dynasty"),
                aliases=data.get("aliases") or [],
                identity=data.get("identity"),
                summary=data.get("summary"),
                status=str(data.get("status") or "pending"),
            )
            session.add(row)
        else:
            if not force and base_version < row.version:
                return {"status": "conflict", "conflict": _conflict("entity changed on server", _normalize_entity(row))}
            for key in (
                "canonical_name", "kind", "dynasty", "courtesy_name", "art_name",
                "posthumous_name", "temple_name", "aliases", "identity", "offices",
                "summary", "status", "birth_raw", "death_raw", "birth_year", "death_year",
            ):
                if key in data and data[key] is not None:
                    setattr(row, key, data[key])
            row.deleted_at = None
            row.version = max(row.version + 1, version or 1)
        await session.flush()
        return {"status": "applied", "data": _normalize_entity(row), "version": row.version}

    async def _apply_relation(
        self, session, entity_id, operation, data, base_version, version,
        updated_at, device_id, force=False,
    ) -> dict[str, Any]:
        row = await session.get(EntityRelation, entity_id)
        if operation == "delete":
            if row is not None:
                row.deleted_at = utcnow()
                row.version += 1
                await session.flush()
            return {"status": "applied", "data": {"id": entity_id, "deleted": True}}
        source_id, target_id = data.get("source_entity_id"), data.get("target_entity_id")
        if not await session.get(HistoricalEntity, source_id) or not await session.get(HistoricalEntity, target_id):
            return {"status": "rejected", "error": "relation endpoints do not exist on this server"}
        if row is None:
            row = EntityRelation(
                id=entity_id,
                source_entity_id=source_id,
                target_entity_id=target_id,
                relation_type=str(data.get("relation_type") or "其他"),
                label=data.get("label"),
                description=data.get("description"),
                status=str(data.get("status") or "inferred"),
                confidence=data.get("confidence"),
                source="manual",
            )
            session.add(row)
        else:
            if not force and base_version < row.version:
                return {"status": "conflict", "conflict": _conflict("relation changed on server", _normalize_entity(row))}
            for key in ("relation_type", "label", "description", "status", "confidence"):
                if key in data and data[key] is not None:
                    setattr(row, key, data[key])
            row.deleted_at = None
            row.version = max(row.version + 1, version or 1)
        await session.flush()
        for evidence in data.get("sources") or []:
            sentence_id = evidence.get("sentence_id")
            if not sentence_id:
                continue
            exists = await session.scalar(
                select(RelationSource.id).where(
                    RelationSource.relation_id == row.id,
                    RelationSource.sentence_id == sentence_id,
                )
            )
            if exists is None:
                sentence = await session.get(Sentence, sentence_id)
                session.add(RelationSource(
                    id=new_id(), relation_id=row.id,
                    book_id=sentence.book_id if sentence else None,
                    chapter_id=sentence.chapter_id if sentence else None,
                    paragraph_id=sentence.paragraph_id if sentence else None,
                    sentence_id=sentence_id,
                    quote=evidence.get("quote") or (sentence.original_text if sentence else None),
                ))
        await session.flush()
        return {"status": "applied", "data": _normalize_entity(row), "version": row.version}

    async def _apply_event(
        self, session, entity_id, operation, data, base_version, version,
        updated_at, device_id, force=False,
    ) -> dict[str, Any]:
        row = await session.get(HistoricalEvent, entity_id)
        if operation == "delete":
            if row is not None:
                row.deleted_at = utcnow()
                row.version += 1
                await session.flush()
            return {"status": "applied", "data": {"id": entity_id, "deleted": True}}
        if row is None:
            parsed = parse_time(
                data.get("time_raw"), era_name=data.get("era_name"),
                reign_year=data.get("reign_year"), dynasty=data.get("dynasty"),
            )
            name = str(data.get("name") or "").strip()
            if not name:
                return {"status": "rejected", "error": "event name is required"}
            row = HistoricalEvent(
                id=entity_id,
                name=name[:300],
                event_type=str(data.get("event_type") or "其他"),
                description=data.get("description"),
                dynasty=data.get("dynasty"),
                time_raw=data.get("time_raw"),
                era_name=data.get("era_name") or parsed.era_name,
                reign_year=data.get("reign_year") or parsed.reign_year,
                ganzhi=data.get("ganzhi"),
                time_start_year=data.get("time_start_year", parsed.year_start),
                time_end_year=data.get("time_end_year", parsed.year_end),
                time_precision=str(data.get("time_precision") or parsed.precision),
                time_note=parsed.note,
                confidence=data.get("confidence"),
                status=str(data.get("status") or "extracted"),
            )
            session.add(row)
        else:
            if not force and base_version < row.version:
                return {"status": "conflict", "conflict": _conflict("event changed on server", _normalize_entity(row))}
            for key in (
                "name", "event_type", "description", "dynasty", "time_raw", "era_name",
                "reign_year", "ganzhi", "time_start_year", "time_end_year",
                "time_precision", "status", "confidence",
            ):
                if key in data and data[key] is not None:
                    setattr(row, key, data[key])
            row.deleted_at = None
            row.version = max(row.version + 1, version or 1)
        await session.flush()
        for evidence in data.get("sources") or []:
            sentence_id = evidence.get("sentence_id")
            if not sentence_id:
                continue
            exists = await session.scalar(
                select(EventSource.id).where(
                    EventSource.event_id == row.id,
                    EventSource.sentence_id == sentence_id,
                )
            )
            if exists is None:
                sentence = await session.get(Sentence, sentence_id)
                session.add(EventSource(
                    id=new_id(), event_id=row.id,
                    book_id=sentence.book_id if sentence else None,
                    chapter_id=sentence.chapter_id if sentence else None,
                    paragraph_id=sentence.paragraph_id if sentence else None,
                    sentence_id=sentence_id,
                    quote=evidence.get("quote") or (sentence.original_text if sentence else None),
                ))
        for participant_id in data.get("participant_entity_ids") or []:
            if not await session.get(HistoricalEntity, participant_id):
                continue
            exists = await session.scalar(
                select(EventParticipant.id).where(
                    EventParticipant.event_id == row.id,
                    EventParticipant.entity_id == participant_id,
                )
            )
            if exists is None:
                session.add(EventParticipant(
                    id=new_id(), event_id=row.id, entity_id=participant_id, role=None
                ))
        await session.flush()
        return {"status": "applied", "data": _normalize_entity(row), "version": row.version}
