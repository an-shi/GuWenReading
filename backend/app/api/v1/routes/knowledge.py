"""Knowledge graph, entity, relation, event and timeline APIs."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_session, require_auth
from app.api.v1.schemas import (
    EntityCreate, EntityUpdate, EventCreate, EventUpdate, ExtractionRequest, MergeRequest,
    RelationCreate,
)
from app.core.errors import AppError, ErrorCode, not_found
from app.core.responses import ok, page_data
from app.core.utils import iso, new_id, utcnow
from app.database.models import (
    EntityRelation, HistoricalEntity,
    HistoricalEvent, RelationSource,
)
from app.modules.knowledge.chronology import parse_time
from app.modules.knowledge.extraction import KnowledgeExtractionService
from app.modules.knowledge.service import (
    create_event, create_relation, entity_detail, event_detail, get_entity,
    list_entities, list_events, merge_entities, relation_graph, serialize_entity,
    serialize_event, timeline,
)
from app.modules.search.service import search_entities, search_events, search_text
from app.modules.task_manager.service import serialize_task

router = APIRouter(tags=["knowledge"], dependencies=[Depends(require_auth)])


@router.get("/entities")
async def entities(
    q: str | None = Query(default=None),
    kind: str | None = Query(default=None),
    dynasty: str | None = Query(default=None),
    status: str | None = Query(default=None),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=30, ge=1, le=100),
    session: AsyncSession = Depends(get_session),
):
    rows, total = await list_entities(
        session, query=q, kind=kind, dynasty=dynasty, status=status,
        page=page, page_size=page_size,
    )
    return ok(page_data([serialize_entity(row) for row in rows], total, page, page_size))


@router.get("/entities/search")
async def entity_search(
    q: str = Query(min_length=1),
    limit: int = Query(default=20, ge=1, le=100),
    session: AsyncSession = Depends(get_session),
):
    return ok(await search_entities(session, q, limit=limit))


@router.get("/entities/{entity_id}")
async def entity_get(entity_id: str, session: AsyncSession = Depends(get_session)):
    return ok(await entity_detail(session, entity_id))


@router.get("/entities/{entity_id}/mentions")
async def entity_mentions(entity_id: str, session: AsyncSession = Depends(get_session)):
    detail = await entity_detail(session, entity_id)
    return ok(detail["mentions"])


@router.post("/entities", status_code=201)
async def entity_create(body: EntityCreate, session: AsyncSession = Depends(get_session)):
    existing = await session.scalar(
        select(HistoricalEntity).where(
            HistoricalEntity.canonical_name == body.canonical_name.strip(),
            HistoricalEntity.deleted_at.is_(None),
        )
    )
    if existing is not None:
        raise AppError(
            ErrorCode.CONFLICT, "An entity with this canonical name already exists",
            status_code=409, details={"entity_id": existing.id},
        )
    entity = HistoricalEntity(
        id=new_id(),
        **body.model_dump(exclude={"canonical_name"}),
        canonical_name=body.canonical_name.strip(),
    )
    session.add(entity)
    await session.commit()
    await session.refresh(entity)
    return ok(serialize_entity(entity))


@router.put("/entities/{entity_id}")
async def entity_update(
    entity_id: str,
    body: EntityUpdate,
    session: AsyncSession = Depends(get_session),
):
    entity = await get_entity(session, entity_id)
    for key, value in body.model_dump(exclude_unset=True).items():
        setattr(entity, key, value)
    entity.version += 1
    entity.updated_at = utcnow()
    await session.commit()
    await session.refresh(entity)
    return ok(serialize_entity(entity))


@router.post("/entities/{entity_id}/merge")
async def entity_merge(
    entity_id: str,
    body: MergeRequest,
    session: AsyncSession = Depends(get_session),
):
    entity = await merge_entities(session, entity_id, body.source_entity_ids)
    return ok(serialize_entity(entity), message="merged")


def _relation_payload(
    relation: EntityRelation, source: HistoricalEntity | None, target: HistoricalEntity | None
) -> dict[str, Any]:
    return {
        "id": relation.id,
        "source_entity_id": relation.source_entity_id,
        "target_entity_id": relation.target_entity_id,
        "source_name": source.canonical_name if source else None,
        "target_name": target.canonical_name if target else None,
        "relation_type": relation.relation_type,
        "label": relation.label,
        "description": relation.description,
        "status": relation.status,
        "confidence": relation.confidence,
        "source": relation.source,
        "created_at": iso(relation.created_at),
        "updated_at": iso(relation.updated_at),
    }


@router.get("/relations")
async def relations(
    entity_id: str | None = Query(default=None),
    relation_type: str | None = Query(default=None),
    status: str | None = Query(default=None),
    include_pending: bool = Query(default=True),
    session: AsyncSession = Depends(get_session),
):
    conditions = [EntityRelation.deleted_at.is_(None), EntityRelation.status != "rejected"]
    if entity_id:
        conditions.append(or_(
            EntityRelation.source_entity_id == entity_id,
            EntityRelation.target_entity_id == entity_id,
        ))
    if relation_type:
        conditions.append(EntityRelation.relation_type == relation_type)
    if status:
        conditions.append(EntityRelation.status == status)
    elif not include_pending:
        conditions.append(EntityRelation.status.in_(["explicit", "confirmed"]))
    rows = list((await session.scalars(
        select(EntityRelation).where(*conditions).limit(1000)
    )).all())
    entity_ids = {
        relation.source_entity_id for relation in rows
    } | {relation.target_entity_id for relation in rows}
    entities = {
        row.id: row for row in (await session.scalars(
            select(HistoricalEntity).where(HistoricalEntity.id.in_(entity_ids))
        )).all()
    } if entity_ids else {}
    counts = dict((await session.execute(
        select(RelationSource.relation_id, func.count())
        .where(RelationSource.relation_id.in_([relation.id for relation in rows]))
        .group_by(RelationSource.relation_id)
    )).all()) if rows else {}
    return ok([
        {
            **_relation_payload(
                relation, entities.get(relation.source_entity_id),
                entities.get(relation.target_entity_id),
            ),
            "source_count": counts.get(relation.id, 0),
        }
        for relation in rows
    ])


@router.post("/relations", status_code=201)
async def relation_create(body: RelationCreate, session: AsyncSession = Depends(get_session)):
    relation = await create_relation(
        session,
        source_entity_id=body.source_entity_id,
        target_entity_id=body.target_entity_id,
        relation_type=body.relation_type,
        label=body.label,
        description=body.description,
        status=body.status,
        confidence=body.confidence,
        evidence=body.evidence,
    )
    return ok({
        "id": relation.id,
        "source_entity_id": relation.source_entity_id,
        "target_entity_id": relation.target_entity_id,
        "relation_type": relation.relation_type,
        "status": relation.status,
    })


@router.put("/relations/{relation_id}/review")
async def relation_review(
    relation_id: str,
    status: str = Query(pattern="^(explicit|inferred|confirmed|rejected)$"),
    session: AsyncSession = Depends(get_session),
):
    relation = await session.get(EntityRelation, relation_id)
    if relation is None or relation.deleted_at is not None:
        raise not_found("EntityRelation", relation_id)
    relation.status = status
    relation.version += 1
    relation.updated_at = utcnow()
    await session.commit()
    return ok({"id": relation.id, "status": relation.status})


@router.get("/graph")
async def graph(
    center_id: str | None = Query(default=None),
    depth: int = Query(default=2, ge=1, le=4),
    dynasty: str | None = Query(default=None),
    relation_type: str | None = Query(default=None),
    book_id: str | None = Query(default=None),
    include_pending: bool = Query(default=True),
    max_nodes: int = Query(default=200, ge=10, le=500),
    session: AsyncSession = Depends(get_session),
):
    return ok(await relation_graph(
        session, center_id=center_id, depth=depth, dynasty=dynasty,
        relation_type=relation_type, book_id=book_id,
        include_pending=include_pending, max_nodes=max_nodes,
    ))


@router.get("/events")
async def events(
    q: str | None = Query(default=None),
    event_type: str | None = Query(default=None),
    dynasty: str | None = Query(default=None),
    status: str | None = Query(default=None),
    year_from: int | None = Query(default=None),
    year_to: int | None = Query(default=None),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=30, ge=1, le=100),
    session: AsyncSession = Depends(get_session),
):
    rows, total = await list_events(
        session, query=q, event_type=event_type, dynasty=dynasty, status=status,
        year_from=year_from, year_to=year_to, page=page, page_size=page_size,
    )
    return ok(page_data([serialize_event(row) for row in rows], total, page, page_size))


@router.get("/events/{event_id}")
async def event_get(event_id: str, session: AsyncSession = Depends(get_session)):
    return ok(await event_detail(session, event_id))


@router.post("/events", status_code=201)
async def event_create(body: EventCreate, session: AsyncSession = Depends(get_session)):
    event = await create_event(
        session,
        name=body.name,
        event_type=body.event_type,
        description=body.description,
        dynasty=body.dynasty,
        time_raw=body.time_raw,
        era_name=body.era_name,
        reign_year=body.reign_year,
        ganzhi=body.ganzhi,
        time_start_year=body.time_start_year,
        time_end_year=body.time_end_year,
        time_precision=body.time_precision,
        status=body.status,
        confidence=body.confidence,
        participant_entity_ids=body.participant_entity_ids,
        evidence=body.evidence,
    )
    return ok(serialize_event(event))


@router.put("/events/{event_id}")
async def event_update(
    event_id: str,
    body: EventUpdate,
    session: AsyncSession = Depends(get_session),
):
    event = await session.get(HistoricalEvent, event_id)
    if event is None or event.deleted_at is not None:
        raise not_found("HistoricalEvent", event_id)
    values = body.model_dump(exclude_unset=True)
    for key, value in values.items():
        setattr(event, key, value)
    if any(key in values for key in ("time_raw", "era_name", "reign_year", "ganzhi")):
        parsed = parse_time(
            event.time_raw, era_name=event.era_name, reign_year=event.reign_year,
            dynasty=event.dynasty,
        )
        if "time_start_year" not in values:
            event.time_start_year = parsed.year_start
        if "time_end_year" not in values:
            event.time_end_year = parsed.year_end
        if "time_precision" not in values:
            event.time_precision = parsed.precision
        event.time_note = parsed.note
    event.version += 1
    event.updated_at = utcnow()
    await session.commit()
    await session.refresh(event)
    return ok(serialize_event(event))


@router.put("/events/{event_id}/review")
async def event_review(
    event_id: str,
    status: str = Query(pattern="^(extracted|confirmed|rejected)$"),
    session: AsyncSession = Depends(get_session),
):
    event = await session.get(HistoricalEvent, event_id)
    if event is None or event.deleted_at is not None:
        raise not_found("HistoricalEvent", event_id)
    event.status = status
    event.version += 1
    event.updated_at = utcnow()
    await session.commit()
    return ok({"id": event.id, "status": event.status})


@router.get("/timeline")
async def get_timeline(
    year_from: int | None = Query(default=None),
    year_to: int | None = Query(default=None),
    event_type: str | None = Query(default=None),
    dynasty: str | None = Query(default=None),
    include_extracted: bool = Query(default=True),
    limit: int = Query(default=500, ge=1, le=2000),
    session: AsyncSession = Depends(get_session),
):
    return ok(await timeline(
        session, year_from=year_from, year_to=year_to, event_type=event_type,
        dynasty=dynasty, include_extracted=include_extracted, limit=limit,
    ))


@router.post("/knowledge/extract", status_code=202)
async def extract_knowledge(
    body: ExtractionRequest,
    request: Request,
    session: AsyncSession = Depends(get_session),
):
    service = KnowledgeExtractionService(
        request.app.state.settings, adapter_factory=request.app.state.adapter_factory
    )
    task = await service.create_task(
        session,
        body.chapter_id,
        model_id=body.model_id,
        extract_entities=body.extract_entities,
        extract_relations=body.extract_relations,
        extract_events=body.extract_events,
    )
    request.app.state.task_runner.enqueue(task.id)
    return ok(serialize_task(task), message="queued")


@router.get("/search")
async def search(
    q: str = Query(min_length=1),
    scope: str = Query(default="all", pattern="^(all|original|translation)$"),
    book_id: str | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    session: AsyncSession = Depends(get_session),
):
    text_hits = await search_text(session, q, scope=scope, book_id=book_id, limit=limit)
    entities = await search_entities(session, q, limit=min(limit, 20))
    events = await search_events(session, q, limit=min(limit, 20))
    return ok({
        "query": q,
        "sentences": text_hits,
        "entities": entities,
        "events": events,
        "total": len(text_hits) + len(entities) + len(events),
    })


@router.get("/assistant/sessions")
async def assistant_sessions(
    book_id: str | None = Query(default=None),
    limit: int = Query(default=50, ge=1, le=200),
    session: AsyncSession = Depends(get_session),
):
    from app.database.models import AssistantSession

    statement = select(AssistantSession)
    if book_id:
        statement = statement.where(AssistantSession.book_id == book_id)
    rows = list((await session.scalars(
        statement.order_by(AssistantSession.updated_at.desc()).limit(limit)
    )).all())
    return ok([
        {
            "id": row.id, "title": row.title, "book_id": row.book_id,
            "chapter_id": row.chapter_id, "updated_at": iso(row.updated_at),
        }
        for row in rows
    ])


@router.get("/assistant/sessions/{session_id}")
async def assistant_session_detail(
    session_id: str,
    session: AsyncSession = Depends(get_session),
):
    from app.database.models import AssistantMessage, AssistantSession

    row = await session.get(AssistantSession, session_id)
    if row is None:
        raise not_found("AssistantSession", session_id)
    messages = list((await session.scalars(
        select(AssistantMessage)
        .where(AssistantMessage.session_id == session_id)
        .order_by(AssistantMessage.created_at)
    )).all())
    return ok({
        "session": {
            "id": row.id, "title": row.title, "book_id": row.book_id,
            "chapter_id": row.chapter_id, "created_at": iso(row.created_at),
        },
        "messages": [
            {
                "id": message.id, "role": message.role, "content": message.content,
                "citations": message.citations or [], "model_name": message.model_name,
                "created_at": iso(message.created_at),
            }
            for message in messages
        ],
    })
