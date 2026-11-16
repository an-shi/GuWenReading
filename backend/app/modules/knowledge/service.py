"""Knowledge-base CRUD, disambiguation/merge, graph and timeline queries."""

from __future__ import annotations

from collections import defaultdict, deque
from typing import Any

from sqlalchemy import String, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError, ErrorCode, not_found
from app.core.utils import iso, new_id, utcnow
from app.database.models import (
    Book, Chapter, EntityMention, EntityRelation, EventParticipant, EventSource,
    HistoricalEntity, HistoricalEvent, RelationSource, Sentence,
)


def serialize_entity(entity: HistoricalEntity, **extra: Any) -> dict[str, Any]:
    payload = {
        "id": entity.id,
        "canonical_name": entity.canonical_name,
        "kind": entity.kind,
        "dynasty": entity.dynasty,
        "courtesy_name": entity.courtesy_name,
        "art_name": entity.art_name,
        "posthumous_name": entity.posthumous_name,
        "temple_name": entity.temple_name,
        "aliases": entity.aliases or [],
        "birth_raw": entity.birth_raw,
        "death_raw": entity.death_raw,
        "birth_year": entity.birth_year,
        "death_year": entity.death_year,
        "identity": entity.identity,
        "offices": entity.offices or [],
        "summary": entity.summary,
        "status": entity.status,
        "confidence": entity.confidence,
        "created_at": iso(entity.created_at),
        "updated_at": iso(entity.updated_at),
        "version": entity.version,
    }
    payload.update(extra)
    return payload


async def list_entities(
    session: AsyncSession,
    *,
    query: str | None = None,
    kind: str | None = None,
    dynasty: str | None = None,
    status: str | None = None,
    page: int = 1,
    page_size: int = 30,
) -> tuple[list[HistoricalEntity], int]:
    conditions = [HistoricalEntity.deleted_at.is_(None)]
    if query:
        pattern = f"%{query.strip()}%"
        conditions.append(or_(
            HistoricalEntity.canonical_name.like(pattern),
            HistoricalEntity.aliases.cast(String).like(pattern),
            HistoricalEntity.summary.like(pattern),
        ))
    if kind:
        conditions.append(HistoricalEntity.kind == kind)
    if dynasty:
        conditions.append(HistoricalEntity.dynasty == dynasty)
    if status:
        conditions.append(HistoricalEntity.status == status)
    else:
        conditions.append(HistoricalEntity.status != "rejected")
    total = await session.scalar(
        select(func.count()).select_from(HistoricalEntity).where(*conditions)
    ) or 0
    rows = list((await session.scalars(
        select(HistoricalEntity).where(*conditions)
        .order_by(HistoricalEntity.canonical_name)
        .offset((page - 1) * page_size).limit(page_size)
    )).all())
    return rows, total


async def get_entity(session: AsyncSession, entity_id: str) -> HistoricalEntity:
    entity = await session.get(HistoricalEntity, entity_id)
    if entity is None or entity.deleted_at is not None:
        raise not_found("HistoricalEntity", entity_id)
    return entity


async def entity_detail(session: AsyncSession, entity_id: str) -> dict[str, Any]:
    entity = await get_entity(session, entity_id)
    mentions = (await session.execute(
        select(EntityMention, Sentence, Chapter, Book)
        .join(Sentence, Sentence.id == EntityMention.sentence_id)
        .join(Chapter, Chapter.id == Sentence.chapter_id)
        .join(Book, Book.id == Sentence.book_id)
        .where(EntityMention.entity_id == entity.id)
        .order_by(EntityMention.created_at.desc())
        .limit(200)
    )).all()
    relations = (await session.execute(
        select(EntityRelation)
        .where(
            EntityRelation.deleted_at.is_(None),
            EntityRelation.status != "rejected",
            or_(
                EntityRelation.source_entity_id == entity.id,
                EntityRelation.target_entity_id == entity.id,
            ),
        )
    )).scalars().all()
    other_ids = {
        relation.target_entity_id if relation.source_entity_id == entity.id
        else relation.source_entity_id
        for relation in relations
    }
    others = {
        row.id: row for row in (await session.scalars(
            select(HistoricalEntity).where(HistoricalEntity.id.in_(other_ids))
        )).all()
    } if other_ids else {}
    source_map = await _relation_sources(session, [relation.id for relation in relations])
    relation_payload = []
    for relation in relations:
        other_id = (
            relation.target_entity_id if relation.source_entity_id == entity.id
            else relation.source_entity_id
        )
        other = others.get(other_id)
        relation_payload.append({
            "id": relation.id,
            "source_entity_id": relation.source_entity_id,
            "target_entity_id": relation.target_entity_id,
            "direction": "outgoing" if relation.source_entity_id == entity.id else "incoming",
            "other_entity_id": other_id,
            "other_entity_name": other.canonical_name if other else None,
            "relation_type": relation.relation_type,
            "label": relation.label,
            "description": relation.description,
            "status": relation.status,
            "confidence": relation.confidence,
            "sources": source_map.get(relation.id, []),
        })
    return serialize_entity(
        entity,
        mentions=[
            {
                "id": mention.id,
                "sentence_id": mention.sentence_id,
                "surface_text": mention.surface_text,
                "quote": sentence.original_text,
                "book_id": book.id,
                "book_title": book.title,
                "chapter_id": chapter.id,
                "chapter_title": chapter.title,
                "source": mention.source,
                "status": mention.status,
                "confidence": mention.confidence,
            }
            for mention, sentence, chapter, book in mentions
        ],
        relations=relation_payload,
        mention_count=len(mentions),
    )


async def _relation_sources(
    session: AsyncSession, relation_ids: list[str]
) -> dict[str, list[dict[str, Any]]]:
    if not relation_ids:
        return {}
    rows = (await session.execute(
        select(RelationSource, Book, Chapter)
        .outerjoin(Book, Book.id == RelationSource.book_id)
        .outerjoin(Chapter, Chapter.id == RelationSource.chapter_id)
        .where(RelationSource.relation_id.in_(relation_ids))
        .order_by(RelationSource.created_at)
    )).all()
    mapping: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for source, book, chapter in rows:
        mapping[source.relation_id].append({
            "id": source.id,
            "book_id": source.book_id,
            "book_title": book.title if book else None,
            "chapter_id": source.chapter_id,
            "chapter_title": chapter.title if chapter else None,
            "sentence_id": source.sentence_id,
            "quote": source.quote,
        })
    return mapping


async def merge_entities(
    session: AsyncSession, target_id: str, source_ids: list[str]
) -> HistoricalEntity:
    target = await get_entity(session, target_id)
    cleaned = [entity_id for entity_id in source_ids if entity_id != target_id]
    if not cleaned:
        raise AppError(ErrorCode.VALIDATION_ERROR, "No source entities to merge", status_code=422)
    sources = list((await session.scalars(
        select(HistoricalEntity).where(HistoricalEntity.id.in_(cleaned))
    )).all())
    aliases = list(dict.fromkeys((target.aliases or []) + [target.canonical_name]))
    for entity in sources:
        aliases.extend([entity.canonical_name, *(entity.aliases or [])])
        if not target.summary and entity.summary:
            target.summary = entity.summary
        if not target.dynasty and entity.dynasty:
            target.dynasty = entity.dynasty
        if not target.identity and entity.identity:
            target.identity = entity.identity
        await update_mentions_entity(session, entity.id, target.id)
        await update_relation_entity(session, entity.id, target.id)
        participants = list((await session.scalars(
            select(EventParticipant).where(EventParticipant.entity_id == entity.id)
        )).all())
        for participant in participants:
            duplicate = await session.scalar(
                select(EventParticipant.id).where(
                    EventParticipant.event_id == participant.event_id,
                    EventParticipant.entity_id == target.id,
                    EventParticipant.role == participant.role,
                )
            )
            if duplicate:
                await session.delete(participant)
            else:
                participant.entity_id = target.id
        entity.deleted_at = utcnow()
        entity.status = "rejected"
        entity.version += 1
    target.aliases = list(dict.fromkeys(
        alias for alias in aliases if alias and alias != target.canonical_name
    ))
    target.version += 1
    target.updated_at = utcnow()
    await session.commit()
    await session.refresh(target)
    return target


async def update_mentions_entity(session: AsyncSession, old_id: str, new_id: str) -> None:
    rows = list((await session.scalars(
        select(EntityMention).where(EntityMention.entity_id == old_id)
    )).all())
    for row in rows:
        row.entity_id = new_id
        row.version += 1


async def update_relation_entity(session: AsyncSession, old_id: str, new_id: str) -> None:
    rows = list((await session.scalars(
        select(EntityRelation).where(
            or_(
                EntityRelation.source_entity_id == old_id,
                EntityRelation.target_entity_id == old_id,
            )
        )
    )).all())
    for row in rows:
        if row.source_entity_id == old_id:
            row.source_entity_id = new_id
        if row.target_entity_id == old_id:
            row.target_entity_id = new_id
        row.version += 1


async def relation_graph(
    session: AsyncSession,
    *,
    center_id: str | None = None,
    depth: int = 2,
    dynasty: str | None = None,
    relation_type: str | None = None,
    book_id: str | None = None,
    include_pending: bool = True,
    max_nodes: int = 200,
) -> dict[str, Any]:
    conditions = [EntityRelation.deleted_at.is_(None), EntityRelation.status != "rejected"]
    if relation_type:
        conditions.append(EntityRelation.relation_type == relation_type)
    if not include_pending:
        conditions.append(EntityRelation.status.in_(["explicit", "confirmed"]))
    relations = list((await session.scalars(
        select(EntityRelation).where(*conditions).limit(5000)
    )).all())

    if book_id:
        allowed = set((await session.scalars(
            select(RelationSource.relation_id).where(RelationSource.book_id == book_id)
        )).all())
        relations = [relation for relation in relations if relation.id in allowed]

    entities = {
        entity.id: entity for entity in (await session.scalars(
            select(HistoricalEntity).where(HistoricalEntity.deleted_at.is_(None))
        )).all()
    }
    if dynasty:
        entities = {
            entity_id: entity for entity_id, entity in entities.items()
            if entity.dynasty == dynasty
        }
    relations = [
        relation for relation in relations
        if relation.source_entity_id in entities and relation.target_entity_id in entities
    ]

    adjacency: dict[str, set[str]] = defaultdict(set)
    for relation in relations:
        adjacency[relation.source_entity_id].add(relation.target_entity_id)
        adjacency[relation.target_entity_id].add(relation.source_entity_id)

    selected_ids: set[str]
    truncated = False
    if center_id:
        if center_id not in entities:
            raise not_found("HistoricalEntity", center_id)
        selected_ids = {center_id}
        frontier = deque([(center_id, 0)])
        while frontier:
            current, current_depth = frontier.popleft()
            if current_depth >= depth:
                continue
            for neighbor in adjacency.get(current, set()):
                if neighbor not in selected_ids:
                    selected_ids.add(neighbor)
                    frontier.append((neighbor, current_depth + 1))
    else:
        selected_ids = set(adjacency.keys())

    if len(selected_ids) > max_nodes:
        truncated = True
        if center_id and center_id in selected_ids:
            ordered = [center_id] + sorted(selected_ids - {center_id})
        else:
            ordered = sorted(selected_ids, key=lambda entity_id: -len(adjacency.get(entity_id, set())))
        selected_ids = set(ordered[:max_nodes])

    visible_relations = [
        relation for relation in relations
        if relation.source_entity_id in selected_ids and relation.target_entity_id in selected_ids
    ]
    degree: dict[str, int] = defaultdict(int)
    for relation in visible_relations:
        degree[relation.source_entity_id] += 1
        degree[relation.target_entity_id] += 1
    source_map = await _relation_sources(session, [relation.id for relation in visible_relations][:2000])

    nodes = [
        {
            "id": entity.id,
            "label": entity.canonical_name,
            "kind": entity.kind,
            "dynasty": entity.dynasty,
            "status": entity.status,
            "degree": degree.get(entity.id, 0),
        }
        for entity_id, entity in entities.items() if entity_id in selected_ids
    ]
    edges = [
        {
            "id": relation.id,
            "source": relation.source_entity_id,
            "target": relation.target_entity_id,
            "label": relation.label or relation.relation_type,
            "relation_type": relation.relation_type,
            "status": relation.status,
            "confidence": relation.confidence,
            "description": relation.description,
            "sources": source_map.get(relation.id, []),
        }
        for relation in visible_relations
    ]
    return {"nodes": nodes, "edges": edges, "truncated": truncated, "center_id": center_id}


async def create_relation(
    session: AsyncSession,
    *,
    source_entity_id: str,
    target_entity_id: str,
    relation_type: str,
    label: str | None,
    description: str | None,
    status: str,
    confidence: float | None,
    evidence: list[dict[str, Any]],
) -> EntityRelation:
    if source_entity_id == target_entity_id:
        raise AppError(ErrorCode.VALIDATION_ERROR, "A relation needs two different entities", status_code=422)
    for entity_id in (source_entity_id, target_entity_id):
        await get_entity(session, entity_id)
    relation = EntityRelation(
        id=new_id(),
        source_entity_id=source_entity_id,
        target_entity_id=target_entity_id,
        relation_type=relation_type.strip() or "其他",
        label=label,
        description=description,
        status=status,
        confidence=confidence,
        source="manual",
    )
    session.add(relation)
    await session.flush()
    for item in evidence:
        await _add_relation_evidence(session, relation.id, item)
    await session.commit()
    await session.refresh(relation)
    return relation


async def _add_relation_evidence(
    session: AsyncSession, relation_id: str, evidence: dict[str, Any]
) -> RelationSource | None:
    quote = (evidence.get("quote") or "").strip()
    sentence_id = evidence.get("sentence_id")
    if not quote and not sentence_id:
        return None
    sentence = await session.get(Sentence, sentence_id) if sentence_id else None
    if sentence is not None and not quote:
        quote = sentence.original_text
    source = RelationSource(
        id=new_id(),
        relation_id=relation_id,
        book_id=evidence.get("book_id") or (sentence.book_id if sentence else None),
        chapter_id=evidence.get("chapter_id") or (sentence.chapter_id if sentence else None),
        paragraph_id=evidence.get("paragraph_id") or (sentence.paragraph_id if sentence else None),
        sentence_id=sentence_id,
        quote=quote,
    )
    session.add(source)
    return source


async def create_event(
    session: AsyncSession,
    *,
    name: str,
    event_type: str,
    description: str | None,
    dynasty: str | None,
    time_raw: str | None,
    era_name: str | None,
    reign_year: str | None,
    ganzhi: str | None,
    time_start_year: int | None,
    time_end_year: int | None,
    time_precision: str | None,
    status: str,
    confidence: float | None,
    participant_entity_ids: list[str],
    evidence: list[dict[str, Any]],
    metadata: dict[str, Any] | None = None,
) -> HistoricalEvent:
    from app.modules.knowledge.chronology import parse_time

    parsed = parse_time(
        time_raw, era_name=era_name, reign_year=reign_year, dynasty=dynasty
    )
    start = time_start_year if time_start_year is not None else parsed.year_start
    end = time_end_year if time_end_year is not None else parsed.year_end
    precision = time_precision or parsed.precision
    event = HistoricalEvent(
        id=new_id(),
        name=name.strip()[:300],
        event_type=event_type.strip() or "其他",
        description=description,
        dynasty=dynasty,
        time_raw=time_raw,
        era_name=era_name or parsed.era_name,
        reign_year=reign_year or parsed.reign_year,
        ganzhi=ganzhi,
        time_start_year=start,
        time_end_year=end,
        time_precision=precision,
        time_note=parsed.note,
        confidence=confidence,
        status=status,
        metadata_json=metadata or {},
    )
    session.add(event)
    await session.flush()
    for entity_id in dict.fromkeys(participant_entity_ids):
        if await session.get(HistoricalEntity, entity_id):
            session.add(EventParticipant(
                id=new_id(), event_id=event.id, entity_id=entity_id, role=None
            ))
    for item in evidence:
        await _add_event_evidence(session, event.id, item)
    await session.commit()
    await session.refresh(event)
    return event


async def _add_event_evidence(
    session: AsyncSession, event_id: str, evidence: dict[str, Any]
) -> EventSource | None:
    quote = (evidence.get("quote") or "").strip()
    sentence_id = evidence.get("sentence_id")
    if not quote and not sentence_id:
        return None
    sentence = await session.get(Sentence, sentence_id) if sentence_id else None
    if sentence is not None and not quote:
        quote = sentence.original_text
    source = EventSource(
        id=new_id(),
        event_id=event_id,
        book_id=evidence.get("book_id") or (sentence.book_id if sentence else None),
        chapter_id=evidence.get("chapter_id") or (sentence.chapter_id if sentence else None),
        paragraph_id=evidence.get("paragraph_id") or (sentence.paragraph_id if sentence else None),
        sentence_id=sentence_id,
        quote=quote,
    )
    session.add(source)
    return source


def serialize_event(event: HistoricalEvent, **extra: Any) -> dict[str, Any]:
    payload = {
        "id": event.id,
        "name": event.name,
        "event_type": event.event_type,
        "description": event.description,
        "dynasty": event.dynasty,
        "time_raw": event.time_raw,
        "era_name": event.era_name,
        "reign_year": event.reign_year,
        "ganzhi": event.ganzhi,
        "time_start_year": event.time_start_year,
        "time_end_year": event.time_end_year,
        "time_precision": event.time_precision,
        "time_note": event.time_note,
        "confidence": event.confidence,
        "status": event.status,
        "tags": event.tags or [],
        "created_at": iso(event.created_at),
        "updated_at": iso(event.updated_at),
        "version": event.version,
    }
    payload.update(extra)
    return payload


async def list_events(
    session: AsyncSession,
    *,
    query: str | None = None,
    event_type: str | None = None,
    dynasty: str | None = None,
    status: str | None = None,
    year_from: int | None = None,
    year_to: int | None = None,
    page: int = 1,
    page_size: int = 30,
) -> tuple[list[HistoricalEvent], int]:
    conditions = [HistoricalEvent.deleted_at.is_(None)]
    if query:
        pattern = f"%{query.strip()}%"
        conditions.append(or_(
            HistoricalEvent.name.like(pattern),
            HistoricalEvent.description.like(pattern),
            HistoricalEvent.time_raw.like(pattern),
        ))
    if event_type:
        conditions.append(HistoricalEvent.event_type == event_type)
    if dynasty:
        conditions.append(HistoricalEvent.dynasty == dynasty)
    if status:
        conditions.append(HistoricalEvent.status == status)
    else:
        conditions.append(HistoricalEvent.status != "rejected")
    if year_from is not None:
        conditions.append(HistoricalEvent.time_end_year >= year_from)
    if year_to is not None:
        conditions.append(HistoricalEvent.time_start_year <= year_to)
    total = await session.scalar(
        select(func.count()).select_from(HistoricalEvent).where(*conditions)
    ) or 0
    rows = list((await session.scalars(
        select(HistoricalEvent).where(*conditions)
        .order_by(HistoricalEvent.time_start_year.asc().nulls_last(), HistoricalEvent.name)
        .offset((page - 1) * page_size).limit(page_size)
    )).all())
    return rows, total


async def event_detail(session: AsyncSession, event_id: str) -> dict[str, Any]:
    event = await session.get(HistoricalEvent, event_id)
    if event is None or event.deleted_at is not None:
        raise not_found("HistoricalEvent", event_id)
    participants = (await session.execute(
        select(EventParticipant, HistoricalEntity)
        .join(HistoricalEntity, HistoricalEntity.id == EventParticipant.entity_id)
        .where(EventParticipant.event_id == event_id)
    )).all()
    sources = (await session.execute(
        select(EventSource, Book, Chapter)
        .outerjoin(Book, Book.id == EventSource.book_id)
        .outerjoin(Chapter, Chapter.id == EventSource.chapter_id)
        .where(EventSource.event_id == event_id)
        .order_by(EventSource.created_at)
    )).all()
    return serialize_event(
        event,
        participants=[
            {
                "entity_id": participant.entity_id,
                "name": entity.canonical_name,
                "role": participant.role,
            }
            for participant, entity in participants
        ],
        sources=[
            {
                "id": source.id,
                "book_id": source.book_id,
                "book_title": book.title if book else None,
                "chapter_id": source.chapter_id,
                "chapter_title": chapter.title if chapter else None,
                "sentence_id": source.sentence_id,
                "quote": source.quote,
            }
            for source, book, chapter in sources
        ],
    )


async def timeline(
    session: AsyncSession,
    *,
    year_from: int | None = None,
    year_to: int | None = None,
    event_type: str | None = None,
    dynasty: str | None = None,
    include_extracted: bool = True,
    limit: int = 500,
) -> dict[str, Any]:
    conditions = [HistoricalEvent.deleted_at.is_(None), HistoricalEvent.status != "rejected"]
    if not include_extracted:
        conditions.append(HistoricalEvent.status == "confirmed")
    if event_type:
        conditions.append(HistoricalEvent.event_type == event_type)
    if dynasty:
        conditions.append(HistoricalEvent.dynasty == dynasty)
    if year_from is not None:
        conditions.append(HistoricalEvent.time_end_year >= year_from)
    if year_to is not None:
        conditions.append(HistoricalEvent.time_start_year <= year_to)
    events = list((await session.scalars(
        select(HistoricalEvent).where(*conditions)
        .order_by(HistoricalEvent.time_start_year.asc().nulls_last(), HistoricalEvent.name)
        .limit(limit)
    )).all())
    event_ids = [event.id for event in events]
    participants: dict[str, list[str]] = defaultdict(list)
    sources: dict[str, int] = defaultdict(int)
    if event_ids:
        for event_id, name in (await session.execute(
            select(EventParticipant.event_id, HistoricalEntity.canonical_name)
            .join(HistoricalEntity, HistoricalEntity.id == EventParticipant.entity_id)
            .where(EventParticipant.event_id.in_(event_ids))
        )).all():
            participants[event_id].append(name)
        for event_id, count in (await session.execute(
            select(EventSource.event_id, func.count())
            .where(EventSource.event_id.in_(event_ids))
            .group_by(EventSource.event_id)
        )).all():
            sources[event_id] = count

    dated = []
    undated = []
    for event in events:
        payload = serialize_event(
            event,
            participants=participants.get(event.id, []),
            source_count=sources.get(event.id, 0),
        )
        if event.time_start_year is None:
            undated.append(payload)
        else:
            dated.append(payload)
    return {"events": dated, "undated": undated, "total": len(events)}
