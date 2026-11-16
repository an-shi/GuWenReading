"""AI-assisted entity, relation and event extraction with mandatory evidence.

Extraction output is stored as pending/extracted, never auto-confirmed. Every
mention, relation source and event source points at a real sentence id from the
source chapter.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.ai.json_utils import complete_json
from app.ai.prompts import get_active_prompt, render_prompt
from app.ai.providers import AIClientFactory, ChatMessage
from app.ai.providers.registry import AdapterFactory
from app.core.config import Settings
from app.core.errors import AppError, ErrorCode, not_found
from app.core.logging import get_logger
from app.core.utils import new_id
from app.database.models import (
    Book, Chapter, EntityMention, EntityRelation, EventParticipant, EventSource,
    HistoricalEntity, HistoricalEvent, Paragraph, RelationSource, Sentence, Task,
)
from app.modules.book_manager.queries import get_chapter
from app.modules.knowledge.chronology import parse_time
from app.modules.task_manager.runner import TaskContext
from app.modules.task_manager.service import create_task

logger = get_logger(__name__)
EVENT_TYPES = {"政治", "战争", "外交", "经济", "文化", "社会", "自然灾害", "其他"}
TYPE_MAP = {
    "politics": "政治", "political": "政治", "war": "战争", "military": "战争",
    "diplomacy": "外交", "economy": "经济", "economic": "经济", "culture": "文化",
    "society": "社会", "social": "社会", "disaster": "自然灾害", "other": "其他",
}
RELATION_TYPES = {
    "父子", "母子", "兄弟", "夫妻", "君臣", "主从", "同盟", "敌对", "师生", "任职", "其他",
}


@dataclass
class ExtractionChunk:
    sentences: list[Sentence]
    paragraphs: list[Paragraph]

    def paragraphs_json(self) -> str:
        by_paragraph: dict[str, list[dict[str, str]]] = {}
        for sentence in self.sentences:
            by_paragraph.setdefault(sentence.paragraph_id, []).append(
                {"id": sentence.id, "text": sentence.original_text}
            )
        order = {paragraph.id: paragraph.ordinal for paragraph in self.paragraphs}
        payload = [
            {"paragraph_id": paragraph_id, "sentences": sentences}
            for paragraph_id, sentences in sorted(
                by_paragraph.items(), key=lambda item: order.get(item[0], 0)
            )
        ]
        return json.dumps(payload, ensure_ascii=False)


@dataclass
class ExtractionStats:
    entities_created: int = 0
    entities_matched: int = 0
    mentions_created: int = 0
    relations_created: int = 0
    relation_sources: int = 0
    events_created: int = 0
    events_matched: int = 0
    event_sources: int = 0
    warnings: list[str] = field(default_factory=list)


def build_chunks(paragraphs: list[Paragraph], sentences: list[Sentence], *, max_chars: int = 4500) -> list[ExtractionChunk]:
    sentences_by_paragraph: dict[str, list[Sentence]] = {}
    for sentence in sentences:
        sentences_by_paragraph.setdefault(sentence.paragraph_id, []).append(sentence)
    chunks: list[ExtractionChunk] = []
    current: list[Sentence] = []
    current_chars = 0
    paragraph_ids: set[str] = set()

    def flush() -> None:
        nonlocal current, current_chars, paragraph_ids
        if current:
            chunks.append(ExtractionChunk(
                sentences=list(current),
                paragraphs=[p for p in paragraphs if p.id in paragraph_ids],
            ))
        current = []
        current_chars = 0
        paragraph_ids = set()

    for paragraph in paragraphs:
        paragraph_sentences = sentences_by_paragraph.get(paragraph.id, [])
        paragraph_chars = sum(len(sentence.original_text) for sentence in paragraph_sentences)
        if current and current_chars + paragraph_chars > max_chars:
            flush()
        if paragraph_chars > max_chars:
            if current:
                flush()
            for sentence in paragraph_sentences:
                if current and current_chars + len(sentence.original_text) > max_chars:
                    flush()
                current.append(sentence)
                current_chars += len(sentence.original_text)
                paragraph_ids.add(paragraph.id)
            flush()
            continue
        current.extend(paragraph_sentences)
        current_chars += paragraph_chars
        paragraph_ids.add(paragraph.id)
    flush()
    return chunks


class EntityResolver:
    def __init__(self, entities: list[HistoricalEntity]) -> None:
        self.entities: dict[str, HistoricalEntity] = {}
        self.index: dict[str, set[str]] = {}
        for entity in entities:
            self.add(entity)

    @staticmethod
    def key(name: str) -> str:
        return name.strip().replace(" ", "")

    def add(self, entity: HistoricalEntity) -> None:
        self.entities[entity.id] = entity
        for name in [entity.canonical_name, *(entity.aliases or [])]:
            if name:
                self.index.setdefault(self.key(name), set()).add(entity.id)

    def add_alias(self, entity: HistoricalEntity, alias: str) -> None:
        alias = alias.strip()
        if not alias:
            return
        key = self.key(alias)
        owners = self.index.get(key, set())
        if owners and entity.id not in owners:
            return
        aliases = list(dict.fromkeys([*(entity.aliases or []), alias]))
        if alias != entity.canonical_name:
            entity.aliases = aliases
            self.index.setdefault(key, set()).add(entity.id)

    def resolve(self, name: str, *, kind: str | None = None, dynasty: str | None = None) -> HistoricalEntity | None:
        candidates = [
            self.entities[entity_id]
            for entity_id in self.index.get(self.key(name), set())
            if entity_id in self.entities
        ]
        if len(candidates) > 1:
            if kind:
                candidates = [item for item in candidates if item.kind == kind]
            if dynasty:
                filtered = [item for item in candidates if item.dynasty == dynasty]
                if filtered:
                    candidates = filtered
        return candidates[0] if len(candidates) == 1 else None


class KnowledgeExtractionService:
    def __init__(self, settings: Settings, adapter_factory: AdapterFactory | None = None) -> None:
        self.settings = settings
        self.adapter_factory = adapter_factory

    def _factory(self, session: AsyncSession) -> AIClientFactory:
        return AIClientFactory(session, self.settings, adapter_factory=self.adapter_factory)

    async def create_task(
        self,
        session: AsyncSession,
        chapter_id: str,
        *,
        model_id: str | None = None,
        extract_entities: bool = True,
        extract_relations: bool = True,
        extract_events: bool = True,
    ) -> Task:
        chapter = await get_chapter(session, chapter_id)
        book = await session.get(Book, chapter.book_id)
        if book is None:
            raise not_found("Book", chapter.book_id)
        client = await self._factory(session).resolve(model_id=model_id, purpose="chat")
        return await create_task(
            session,
            task_type="knowledge_extraction",
            title=f"抽取知识《{book.title}》· {chapter.title}"[:300],
            payload={
                "chapter_id": chapter_id,
                "model_id": client.model.id,
                "extract_entities": extract_entities,
                "extract_relations": extract_relations,
                "extract_events": extract_events,
            },
            book_id=book.id,
            chapter_id=chapter_id,
        )

    async def run_task(self, session: AsyncSession, task: Task, ctx: TaskContext) -> dict[str, Any]:
        payload = task.payload or {}
        chapter = await session.get(Chapter, payload.get("chapter_id"))
        if chapter is None:
            raise not_found("Chapter", payload.get("chapter_id"))
        book = await session.get(Book, chapter.book_id)
        if book is None:
            raise not_found("Book", chapter.book_id)
        client = await self._factory(session).resolve(
            model_id=payload.get("model_id"), purpose="chat"
        )
        paragraphs = list((await session.scalars(
            select(Paragraph).where(Paragraph.chapter_id == chapter.id).order_by(Paragraph.ordinal)
        )).all())
        sentences = list((await session.scalars(
            select(Sentence).where(Sentence.chapter_id == chapter.id).order_by(Sentence.ordinal)
        )).all())
        if not sentences:
            return {"status": "completed", "chapter_id": chapter.id, "message": "No text to analyse"}
        chunks = build_chunks(paragraphs, sentences)
        stages = [
            name for name, enabled in (
                ("entities", payload.get("extract_entities", True)),
                ("relations", payload.get("extract_relations", True)),
                ("events", payload.get("extract_events", True)),
            ) if enabled
        ]
        if not stages:
            raise AppError(ErrorCode.VALIDATION_ERROR, "Select at least one extraction stage", status_code=422)

        prompts = {
            "entities": await get_active_prompt(session, self.settings, "entity_extract"),
            "relations": await get_active_prompt(session, self.settings, "relation_extract"),
            "events": await get_active_prompt(session, self.settings, "event_extract"),
        }
        library_entities = list((await session.scalars(
            select(HistoricalEntity).where(
                HistoricalEntity.deleted_at.is_(None),
                HistoricalEntity.status != "rejected",
            )
        )).all())
        resolver = EntityResolver(library_entities)
        stats = ExtractionStats()
        total_steps = len(chunks) * len(stages)
        step = 0
        await ctx.progress(total=total_steps, completed=0, failed=0, progress=0)

        for chunk in chunks:
            ctx.raise_if_cancelled()
            sentence_map = {sentence.id: sentence for sentence in chunk.sentences}
            entities_for_chunk: list[dict[str, Any]] = []
            paragraphs_json = chunk.paragraphs_json()

            if "entities" in stages:
                prompt = prompts["entities"]
                rendered = render_prompt(prompt.template, {
                    "book_title": book.title,
                    "chapter_title": chapter.title,
                    "paragraphs_json": paragraphs_json,
                })
                data, _ = await complete_json(
                    client.adapter, [ChatMessage(role="user", content=rendered)],
                    temperature=0.1, max_tokens=min(client.model.max_output_tokens, 3000),
                    timeout=client.model.timeout_seconds,
                )
                entities_for_chunk = await self._save_entities(
                    session, chunk, data, resolver, stats, book, chapter
                )
                await session.commit()
                step += 1
                await ctx.progress(completed=step, total=total_steps, failed=0)

            if "relations" in stages:
                candidates = entities_for_chunk or [
                    {"name": entity.canonical_name, "kind": entity.kind, "dynasty": entity.dynasty}
                    for entity in resolver.entities.values()
                    if entity.status != "rejected"
                ]
                if candidates:
                    prompt = prompts["relations"]
                    rendered = render_prompt(prompt.template, {
                        "book_title": book.title,
                        "chapter_title": chapter.title,
                        "entities_json": json.dumps(candidates[:120], ensure_ascii=False),
                        "paragraphs_json": paragraphs_json,
                    })
                    data, _ = await complete_json(
                        client.adapter, [ChatMessage(role="user", content=rendered)],
                        temperature=0.1, max_tokens=min(client.model.max_output_tokens, 3000),
                        timeout=client.model.timeout_seconds,
                    )
                    await self._save_relations(
                        session, chunk, data, resolver, sentence_map, stats, prompt.version
                    )
                    await session.commit()
                else:
                    stats.warnings.append("No entities available for relation extraction")
                step += 1
                await ctx.progress(completed=step, total=total_steps, failed=0)

            if "events" in stages:
                prompt = prompts["events"]
                rendered = render_prompt(prompt.template, {
                    "book_title": book.title,
                    "chapter_title": chapter.title,
                    "paragraphs_json": paragraphs_json,
                })
                data, _ = await complete_json(
                    client.adapter, [ChatMessage(role="user", content=rendered)],
                    temperature=0.1, max_tokens=min(client.model.max_output_tokens, 3000),
                    timeout=client.model.timeout_seconds,
                )
                await self._save_events(
                    session, data, resolver, sentence_map, stats, book, chapter, prompt.version
                )
                await session.commit()
                step += 1
                await ctx.progress(completed=step, total=total_steps, failed=0)

        result = {
            "status": "completed",
            "chapter_id": chapter.id,
            "book_id": book.id,
            "model": client.model.name,
            "steps": step,
            "entities_created": stats.entities_created,
            "entities_matched": stats.entities_matched,
            "mentions_created": stats.mentions_created,
            "relations_created": stats.relations_created,
            "relation_sources": stats.relation_sources,
            "events_created": stats.events_created,
            "events_matched": stats.events_matched,
            "event_sources": stats.event_sources,
            "warnings": stats.warnings,
        }
        await ctx.progress(completed=step, total=total_steps, failed=0, progress=100, result=result)
        return result

    async def _save_entities(
        self,
        session: AsyncSession,
        chunk: ExtractionChunk,
        data: Any,
        resolver: EntityResolver,
        stats: ExtractionStats,
        book: Book,
        chapter: Chapter,
    ) -> list[dict[str, Any]]:
        if not isinstance(data, dict):
            return []
        entities = data.get("entities") or []
        mentions = data.get("mentions") or []
        candidates: list[dict[str, Any]] = []
        for raw in entities:
            if not isinstance(raw, dict):
                continue
            name = str(raw.get("name") or "").strip()
            if not name:
                continue
            kind = str(raw.get("kind") or "other").strip() or "other"
            dynasty = (str(raw.get("dynasty")).strip() if raw.get("dynasty") else None) or book.dynasty
            aliases = [str(alias).strip() for alias in (raw.get("aliases") or []) if str(alias).strip()]
            entity = resolver.resolve(name, kind=kind, dynasty=dynasty)
            if entity is not None:
                stats.entities_matched += 1
                for alias in aliases:
                    resolver.add_alias(entity, alias)
            else:
                entity = HistoricalEntity(
                    id=new_id(),
                    canonical_name=name[:200],
                    kind=kind[:30],
                    dynasty=dynasty,
                    aliases=list(dict.fromkeys(alias for alias in aliases if alias != name))[:20],
                    identity=(str(raw.get("identity"))[:200] if raw.get("identity") else None),
                    summary=(str(raw.get("summary")) if raw.get("summary") else None),
                    status="pending",
                    confidence=raw.get("confidence"),
                )
                session.add(entity)
                await session.flush()
                resolver.add(entity)
                stats.entities_created += 1
            candidates.append({
                "id": entity.id, "name": entity.canonical_name, "kind": entity.kind,
                "dynasty": entity.dynasty,
            })

        sentence_ids = {sentence.id for sentence in chunk.sentences}
        for raw in mentions:
            if not isinstance(raw, dict):
                continue
            entity_name = str(raw.get("entity_name") or "").strip()
            sentence_id = raw.get("sentence_id")
            if not entity_name or sentence_id not in sentence_ids:
                continue
            entity = resolver.resolve(entity_name)
            if entity is None:
                continue
            sentence = next(
                (item for item in chunk.sentences if item.id == sentence_id), None
            )
            if sentence is None:
                continue
            surface = str(raw.get("surface_text") or entity.canonical_name).strip()
            if surface not in sentence.original_text and entity.canonical_name not in sentence.original_text:
                continue
            exists = await session.scalar(
                select(EntityMention.id).where(
                    EntityMention.entity_id == entity.id,
                    EntityMention.sentence_id == sentence_id,
                    EntityMention.surface_text == surface[:200],
                )
            )
            if exists:
                continue
            session.add(EntityMention(
                id=new_id(),
                entity_id=entity.id,
                book_id=book.id,
                chapter_id=chapter.id,
                paragraph_id=sentence.paragraph_id,
                sentence_id=sentence.id,
                surface_text=surface[:200],
                source="ai",
                confidence=raw.get("confidence"),
                status="pending",
            ))
            stats.mentions_created += 1
        return candidates

    async def _save_relations(
        self,
        session: AsyncSession,
        chunk: ExtractionChunk,
        data: Any,
        resolver: EntityResolver,
        sentence_map: dict[str, Sentence],
        stats: ExtractionStats,
        prompt_version: int,
    ) -> None:
        if not isinstance(data, dict):
            return
        for raw in data.get("relations") or []:
            if not isinstance(raw, dict):
                continue
            source_name = str(raw.get("source") or "").strip()
            target_name = str(raw.get("target") or "").strip()
            source = resolver.resolve(source_name)
            target = resolver.resolve(target_name)
            if source is None or target is None or source.id == target.id:
                continue
            relation_type = str(raw.get("type") or "其他").strip() or "其他"
            if relation_type not in RELATION_TYPES:
                relation_type = relation_type[:50]
            evidence_ids = [
                str(item) for item in (raw.get("evidence_ids") or [])
                if str(item) in sentence_map
            ]
            if not evidence_ids:
                continue
            explicit = bool(raw.get("explicit"))
            status = "explicit" if explicit else "inferred"
            existing = await session.scalar(
                select(EntityRelation).where(
                    EntityRelation.source_entity_id == source.id,
                    EntityRelation.target_entity_id == target.id,
                    EntityRelation.relation_type == relation_type,
                    EntityRelation.deleted_at.is_(None),
                    EntityRelation.status != "rejected",
                )
            )
            if existing is not None:
                relation = existing
            else:
                relation = EntityRelation(
                    id=new_id(),
                    source_entity_id=source.id,
                    target_entity_id=target.id,
                    relation_type=relation_type,
                    label=raw.get("label"),
                    description=raw.get("description"),
                    status=status,
                    confidence=raw.get("confidence"),
                    source="ai",
                )
                session.add(relation)
                await session.flush()
                stats.relations_created += 1
            existing_sources = set((await session.scalars(
                select(RelationSource.sentence_id).where(
                    RelationSource.relation_id == relation.id
                )
            )).all())
            for sentence_id in dict.fromkeys(evidence_ids):
                if sentence_id in existing_sources:
                    continue
                sentence = sentence_map[sentence_id]
                session.add(RelationSource(
                    id=new_id(),
                    relation_id=relation.id,
                    book_id=sentence.book_id,
                    chapter_id=sentence.chapter_id,
                    paragraph_id=sentence.paragraph_id,
                    sentence_id=sentence_id,
                    quote=sentence.original_text,
                ))
                stats.relation_sources += 1

    async def _save_events(
        self,
        session: AsyncSession,
        data: Any,
        resolver: EntityResolver,
        sentence_map: dict[str, Sentence],
        stats: ExtractionStats,
        book: Book,
        chapter: Chapter,
        prompt_version: int,
    ) -> None:
        if not isinstance(data, dict):
            return
        for raw in data.get("events") or []:
            if not isinstance(raw, dict):
                continue
            name = str(raw.get("name") or "").strip()
            if not name:
                continue
            evidence_ids = [
                str(item) for item in (raw.get("evidence_ids") or [])
                if str(item) in sentence_map
            ]
            if not evidence_ids:
                stats.warnings.append(f"Event without evidence skipped: {name}")
                continue
            event_type = str(raw.get("type") or "其他").strip()
            event_type = TYPE_MAP.get(event_type.lower(), event_type if event_type in EVENT_TYPES else "其他")
            dynasty = (str(raw.get("dynasty")).strip() if raw.get("dynasty") else None) or book.dynasty
            time_raw = str(raw.get("time_raw") or "").strip() or None
            parsed = parse_time(
                time_raw,
                era_name=str(raw.get("era_name") or "").strip() or None,
                reign_year=str(raw.get("reign_year") or "").strip() or None,
                dynasty=dynasty or book.dynasty,
            )
            existing = await session.scalar(
                select(HistoricalEvent).where(
                    HistoricalEvent.deleted_at.is_(None),
                    HistoricalEvent.name == name[:300],
                    HistoricalEvent.time_start_year == parsed.year_start,
                    HistoricalEvent.status != "rejected",
                )
            )
            if existing is not None:
                event = existing
                stats.events_matched += 1
            else:
                event = HistoricalEvent(
                    id=new_id(),
                    name=name[:300],
                    event_type=event_type,
                    description=str(raw.get("description") or "") or None,
                    dynasty=dynasty,
                    time_raw=time_raw,
                    era_name=str(raw.get("era_name") or "").strip() or parsed.era_name,
                    reign_year=str(raw.get("reign_year") or "").strip() or parsed.reign_year,
                    ganzhi=str(raw.get("ganzhi") or "").strip() or None,
                    time_start_year=parsed.year_start,
                    time_end_year=parsed.year_end,
                    time_precision=parsed.precision,
                    time_note=parsed.note,
                    confidence=raw.get("confidence"),
                    status="extracted",
                    metadata_json={
                        "prompt_version": prompt_version,
                        "book_id": book.id,
                        "chapter_id": chapter.id,
                    },
                )
                session.add(event)
                await session.flush()
                stats.events_created += 1
            for participant_name in raw.get("participants") or []:
                entity = resolver.resolve(str(participant_name))
                if entity is None:
                    continue
                duplicate = await session.scalar(
                    select(EventParticipant.id).where(
                        EventParticipant.event_id == event.id,
                        EventParticipant.entity_id == entity.id,
                        EventParticipant.role.is_(None),
                    )
                )
                if duplicate is None:
                    session.add(EventParticipant(
                        id=new_id(), event_id=event.id, entity_id=entity.id, role=None
                    ))
            existing_sources = set((await session.scalars(
                select(EventSource.sentence_id).where(EventSource.event_id == event.id)
            )).all())
            for sentence_id in dict.fromkeys(evidence_ids):
                if sentence_id in existing_sources:
                    continue
                session.add(EventSource(
                    id=new_id(),
                    event_id=event.id,
                    book_id=book.id,
                    chapter_id=chapter.id,
                    paragraph_id=sentence_map[sentence_id].paragraph_id,
                    sentence_id=sentence_id,
                    quote=sentence_map[sentence_id].original_text,
                ))
                stats.event_sources += 1


def make_extraction_handler(settings: Settings, adapter_factory: AdapterFactory | None = None):
    async def handler(session: AsyncSession, task: Task, ctx: TaskContext) -> dict[str, Any]:
        service = KnowledgeExtractionService(settings, adapter_factory=adapter_factory)
        return await service.run_task(session, task, ctx)

    return handler
