"""Chapter-level, batched, resumable AI translation with manual protection."""

from __future__ import annotations

import json
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.ai.json_utils import complete_json
from app.ai.prompts import get_active_prompt, render_prompt
from app.ai.providers import AIClientFactory, AIProviderError, ChatMessage, ResolvedClient
from app.ai.providers.registry import AdapterFactory
from app.core.config import Settings
from app.core.errors import AppError, ErrorCode, not_found
from app.core.logging import get_logger
from app.core.utils import sha256_text, utcnow
from app.database.fts import index_sentence
from app.database.models import (
    Book, Chapter, Paragraph, Sentence, Task, Translation, TranslationCache,
    TranslationReview, TranslationVersion,
)
from app.modules.book_manager.queries import get_chapter
from app.modules.task_manager.runner import TaskCancelled, TaskContext
from app.modules.task_manager.service import create_task
from app.modules.translation.context import (
    TargetSentence, build_batches, build_paragraph_contexts,
    translation_cache_key,
)

logger = get_logger(__name__)


def _translation_params(settings: Settings) -> dict[str, Any]:
    return {
        "temperature": settings.translation_temperature,
        "style": "balanced",
    }


def _parse_translation_payload(data: Any) -> dict[str, str]:
    mapping: dict[str, str] = {}
    entries = data.get("translations") if isinstance(data, dict) else data
    if isinstance(entries, dict):
        for key, value in entries.items():
            if isinstance(value, str) and value.strip():
                mapping[str(key)] = value.strip()
        return mapping
    if not isinstance(entries, list):
        return mapping
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        identifier = entry.get("id")
        text = entry.get("text")
        if identifier is not None and isinstance(text, str) and text.strip():
            mapping[str(identifier)] = text.strip()
    return mapping


class TranslationService:
    def __init__(self, settings: Settings, adapter_factory: AdapterFactory | None = None) -> None:
        self.settings = settings
        self.adapter_factory = adapter_factory

    def _factory(self, session: AsyncSession) -> AIClientFactory:
        return AIClientFactory(session, self.settings, adapter_factory=self.adapter_factory)

    # ------------------------------------------------------------------ queries
    async def _chapter_sentences(
        self, session: AsyncSession, chapter_id: str
    ) -> list[Sentence]:
        statement = (
            select(Sentence)
            .join(Paragraph, Paragraph.id == Sentence.paragraph_id)
            .where(Sentence.chapter_id == chapter_id)
            .order_by(Paragraph.ordinal, Sentence.ordinal)
        )
        return list((await session.scalars(statement)).all())

    async def _existing_translation_ids(
        self, session: AsyncSession, sentence_ids: list[str]
    ) -> set[str]:
        if not sentence_ids:
            return set()
        return set((await session.scalars(
            select(Translation.sentence_id).where(Translation.sentence_id.in_(sentence_ids))
        )).all())

    async def _select_targets(
        self,
        session: AsyncSession,
        chapter_id: str,
        *,
        sentence_ids: list[str] | None = None,
        retranslate: bool = False,
        only_failed: bool = False,
    ) -> list[Sentence]:
        sentences = await self._chapter_sentences(session, chapter_id)
        if sentence_ids:
            allowed = set(sentence_ids)
            sentences = [sentence for sentence in sentences if sentence.id in allowed]
        translated = await self._existing_translation_ids(session, [s.id for s in sentences])
        if retranslate:
            return sentences
        if only_failed:
            return [s for s in sentences if s.translation_state == "failed" and s.id not in translated]
        return [s for s in sentences if s.id not in translated]

    # ------------------------------------------------------------------ task creation
    async def create_chapter_task(
        self,
        session: AsyncSession,
        chapter_id: str,
        *,
        model_id: str | None = None,
        retranslate: bool = False,
        only_failed: bool = False,
    ) -> Task:
        chapter = await get_chapter(session, chapter_id)
        book = await session.get(Book, chapter.book_id)
        if book is None:
            raise not_found("Book", chapter.book_id)
        client = await self._factory(session).resolve(model_id=model_id, purpose="translation")
        targets = await self._select_targets(
            session, chapter_id, retranslate=retranslate, only_failed=only_failed
        )
        if not targets:
            raise AppError(
                ErrorCode.VALIDATION_ERROR,
                "Nothing to translate: every selected sentence already has a translation",
                status_code=422,
            )
        return await create_task(
            session,
            task_type="translation",
            title=f"翻译《{book.title}》· {chapter.title}"[:300],
            payload={
                "chapter_id": chapter_id,
                "model_id": client.model.id,
                "retranslate": retranslate,
                "only_failed": only_failed,
            },
            book_id=book.id,
            chapter_id=chapter_id,
            total=len(targets),
        )

    async def create_sentence_task(
        self,
        session: AsyncSession,
        sentence_id: str,
        *,
        model_id: str | None = None,
        retranslate: bool = False,
    ) -> Task:
        sentence = await session.get(Sentence, sentence_id)
        if sentence is None:
            raise not_found("Sentence", sentence_id)
        chapter = await session.get(Chapter, sentence.chapter_id)
        book = await session.get(Book, sentence.book_id)
        if chapter is None or book is None:
            raise not_found("Sentence", sentence_id)
        existing = await session.scalar(
            select(Translation).where(Translation.sentence_id == sentence_id)
        )
        if existing is not None and not retranslate:
            raise AppError(
                ErrorCode.CONFLICT,
                "This sentence already has a translation; use re-translate",
                status_code=409,
                details={"translation_id": existing.id},
            )
        client = await self._factory(session).resolve(model_id=model_id, purpose="translation")
        return await create_task(
            session,
            task_type="translation",
            title=f"翻译《{book.title}》· 单句"[:300],
            payload={
                "chapter_id": chapter.id,
                "sentence_ids": [sentence_id],
                "model_id": client.model.id,
                "retranslate": retranslate,
            },
            book_id=book.id,
            chapter_id=chapter.id,
            total=1,
        )

    async def create_paragraph_task(
        self,
        session: AsyncSession,
        paragraph_id: str,
        *,
        model_id: str | None = None,
        retranslate: bool = False,
    ) -> Task:
        paragraph = await session.get(Paragraph, paragraph_id)
        if paragraph is None:
            raise not_found("Paragraph", paragraph_id)
        chapter = await session.get(Chapter, paragraph.chapter_id)
        book = await session.get(Book, paragraph.book_id)
        if chapter is None or book is None:
            raise not_found("Paragraph", paragraph_id)
        sentences = list((await session.scalars(
            select(Sentence).where(Sentence.paragraph_id == paragraph_id).order_by(Sentence.ordinal)
        )).all())
        translated = await self._existing_translation_ids(session, [s.id for s in sentences])
        if translated and not retranslate:
            if len(translated) == len(sentences):
                raise AppError(ErrorCode.VALIDATION_ERROR, "Paragraph is already translated", status_code=422)
        targets = sentences if retranslate else [s for s in sentences if s.id not in translated]
        if not targets:
            raise AppError(ErrorCode.VALIDATION_ERROR, "Nothing to translate", status_code=422)
        client = await self._factory(session).resolve(model_id=model_id, purpose="translation")
        return await create_task(
            session,
            task_type="translation",
            title=f"翻译《{book.title}》· 段落"[:300],
            payload={
                "chapter_id": chapter.id,
                "paragraph_id": paragraph_id,
                "sentence_ids": [s.id for s in targets],
                "model_id": client.model.id,
                "retranslate": retranslate,
            },
            book_id=book.id,
            chapter_id=chapter.id,
            total=len(targets),
        )

    async def create_retranslate_task(
        self, session: AsyncSession, translation_id: str, *, model_id: str | None = None
    ) -> Task:
        translation = await session.get(Translation, translation_id)
        if translation is None:
            raise not_found("Translation", translation_id)
        return await self.create_sentence_task(
            session, translation.sentence_id, model_id=model_id, retranslate=True
        )

    # ------------------------------------------------------------------ execution
    async def run_task(self, session: AsyncSession, task: Task, ctx: TaskContext) -> dict[str, Any]:
        payload = task.payload or {}
        chapter_id = payload.get("chapter_id")
        if not chapter_id:
            raise AppError(ErrorCode.VALIDATION_ERROR, "Translation task has no chapter", status_code=500)
        chapter = await session.get(Chapter, chapter_id)
        if chapter is None:
            raise not_found("Chapter", chapter_id)
        book = await session.get(Book, chapter.book_id)
        if book is None:
            raise not_found("Book", chapter.book_id)

        client = await self._factory(session).resolve(
            model_id=payload.get("model_id"), purpose="translation"
        )
        prompt = await get_active_prompt(session, self.settings, "translation")
        params = _translation_params(self.settings)

        targets = await self._select_targets(
            session,
            chapter_id,
            sentence_ids=payload.get("sentence_ids") or None,
            retranslate=bool(payload.get("retranslate")),
            only_failed=bool(payload.get("only_failed")),
        )
        if not targets:
            await ctx.progress(completed=0, total=0, failed=0, progress=100)
            return {
                "status": "completed", "message": "Nothing to translate",
                "chapter_id": chapter_id, "total": 0, "completed": 0, "failed": 0,
            }

        paragraphs = list((await session.scalars(
            select(Paragraph).where(Paragraph.chapter_id == chapter_id).order_by(Paragraph.ordinal)
        )).all())
        sentence_map = {sentence.id: sentence for sentence in targets}
        existing_translations = {
            row.sentence_id: row for row in (await session.scalars(
                select(Translation).where(Translation.sentence_id.in_(list(sentence_map)))
            )).all()
        }

        total = len(targets)
        await ctx.progress(completed=0, total=total, failed=0, progress=0)
        for sentence in targets:
            if sentence.id not in existing_translations:
                sentence.translation_state = "queued"
                sentence.translation_error = None
        await session.commit()

        contexts = build_paragraph_contexts(paragraphs)
        cache_keys: dict[str, str] = {}
        for sentence in targets:
            context = contexts.get(sentence.paragraph_id)
            if context is None:
                continue
            cache_keys[sentence.id] = translation_cache_key(
                source_text=sentence.original_text,
                context_hash=context.context_hash,
                provider_id=client.provider.id,
                model_id=client.model.id,
                prompt_version=prompt.version,
                params=params,
            )

        completed = 0
        failed = 0
        cached = 0
        failed_ids: set[str] = set()
        completed_ids: set[str] = set()

        cache_hits = await self._load_cache(session, list(cache_keys.values()))
        remaining: list[TargetSentence] = []
        title = f"{book.title} · {chapter.title}"
        for sentence in targets:
            key = cache_keys.get(sentence.id)
            hit = cache_hits.get(key) if key else None
            if hit is not None:
                key = key or ""
                await self._save_ai_translation(
                    session, sentence, hit.translated_text, client=client,
                    prompt_version=prompt.version, cache_key=key, title=title,
                )
                hit.hit_count += 1
                hit.last_used_at = utcnow()
                completed += 1
                cached += 1
                completed_ids.add(sentence.id)
            else:
                remaining.append(TargetSentence(
                    id=sentence.id,
                    text=sentence.original_text,
                    paragraph_id=sentence.paragraph_id,
                    start_offset=sentence.start_offset,
                    end_offset=sentence.end_offset,
                ))
        if cached:
            await session.commit()
            await self.refresh_counts(session, book.id, chapter.id)
            await ctx.progress(completed=completed, total=total, failed=failed)

        budget = max(400, min(
            self.settings.translation_batch_chars,
            max(600, (client.model.context_window - client.model.max_output_tokens - 2000) // 2),
        ))
        batches = build_batches(
            remaining,
            paragraphs=paragraphs,
            max_chars=budget,
            context_chars=self.settings.translation_context_chars,
        )

        abort_reason: str | None = None
        try:
            for batch in batches:
                if abort_reason:
                    for item in batch.items:
                        failed += 1
                        failed_ids.add(item.id)
                        self._mark_failed(sentence_map[item.id], item.id in existing_translations, abort_reason)
                    continue
                ctx.raise_if_cancelled()
                for item in batch.items:
                    sentence = sentence_map[item.id]
                    if item.id not in existing_translations:
                        sentence.translation_state = "translating"
                        sentence.translation_error = None
                await session.commit()
                prompt_text = render_prompt(prompt.template, {
                    "book_title": book.title,
                    "author": book.author or "未知",
                    "dynasty": book.dynasty or "未知",
                    "chapter_title": chapter.title,
                    "context_before": batch.context_before,
                    "context_after": batch.context_after,
                    "items_json": json.dumps(
                        [{"id": item.id, "text": item.text} for item in batch.items],
                        ensure_ascii=False,
                    ),
                })
                messages = [ChatMessage(role="user", content=prompt_text)]

                try:
                    data, _result = await complete_json(
                        client.adapter,
                        messages,
                        temperature=self.settings.translation_temperature,
                        max_tokens=min(
                            client.model.max_output_tokens,
                            max(512, sum(len(item.text) for item in batch.items) * 2 + 400),
                        ),
                        timeout=client.model.timeout_seconds,
                    )
                    ctx.raise_if_cancelled()
                    mapping = _parse_translation_payload(data)
                    if not mapping:
                        raise AIProviderError("AI returned no usable translations")
                except TaskCancelled:
                    raise
                except Exception as exc:
                    error_message = str(exc)[:1000] or exc.__class__.__name__
                    logger.warning("translation_batch_failed", chapter_id=chapter.id, error=error_message)
                    for item in batch.items:
                        failed += 1
                        failed_ids.add(item.id)
                        self._mark_failed(
                            sentence_map[item.id], item.id in existing_translations, error_message
                        )
                    await session.commit()
                    await ctx.progress(completed=completed, total=total, failed=failed)
                    if isinstance(exc, AIProviderError) and not exc.retryable:
                        abort_reason = error_message
                    continue

                for item in batch.items:
                    sentence = sentence_map[item.id]
                    translated = mapping.get(item.id)
                    if not translated:
                        failed += 1
                        failed_ids.add(item.id)
                        self._mark_failed(
                            sentence, item.id in existing_translations,
                            "Model omitted this sentence; retry the task to fill it",
                        )
                        continue
                    outcome = await self._save_ai_translation(
                        session, sentence, translated, client=client,
                        prompt_version=prompt.version, cache_key=cache_keys.get(item.id),
                        title=title,
                    )
                    if outcome == "review":
                        logger.info("manual_translation_protected", sentence_id=sentence.id)
                    if cache_keys.get(item.id):
                        await self._store_cache(
                            session,
                            key=cache_keys[item.id],
                            sentence=sentence,
                            context_hash=contexts[sentence.paragraph_id].context_hash,
                            client=client,
                            prompt_version=prompt.version,
                            text=translated,
                            params=params,
                        )
                    completed += 1
                    completed_ids.add(sentence.id)
                await session.commit()
                await self.refresh_counts(session, book.id, chapter.id)
                await ctx.progress(completed=completed, total=total, failed=failed)
        except TaskCancelled:
            await self._reset_pending_states(session, targets, existing_translations)
            raise

        await self._reset_pending_states(session, targets, existing_translations)
        await self.refresh_counts(session, book.id, chapter.id)
        await self.refresh_counts(session, book.id, chapter.id)

        status = "completed"
        if failed and not completed:
            status = "failed"
        elif failed:
            status = "partial"
        if abort_reason and status == "completed":
            status = "partial"
        result = {
            "status": status,
            "chapter_id": chapter.id,
            "book_id": book.id,
            "model": client.model.name,
            "provider": client.provider.name,
            "prompt_version": prompt.version,
            "total": total,
            "completed": completed,
            "cached": cached,
            "failed": failed,
            "abort_reason": abort_reason,
        }
        await ctx.progress(
            completed=completed, total=total, failed=failed,
            progress=100 if status != "failed" else None, result=result,
        )
        return result

    def _mark_failed(self, sentence: Sentence, had_translation: bool, message: str) -> None:
        sentence.translation_error = message[:1000]
        sentence.translation_state = "completed" if had_translation else "failed"

    async def _load_cache(
        self, session: AsyncSession, keys: list[str]
    ) -> dict[str, TranslationCache]:
        found: dict[str, TranslationCache] = {}
        unique = [key for key in keys if key]
        for start in range(0, len(unique), 400):
            chunk = unique[start : start + 400]
            rows = list((await session.scalars(
                select(TranslationCache).where(TranslationCache.cache_key.in_(chunk))
            )).all())
            for row in rows:
                found[row.cache_key] = row
        return found

    async def _store_cache(
        self,
        session: AsyncSession,
        *,
        key: str,
        sentence: Sentence,
        context_hash: str,
        client: ResolvedClient,
        prompt_version: int,
        text: str,
        params: dict,
    ) -> None:
        existing = await session.get(TranslationCache, key)
        if existing is not None:
            existing.translated_text = text
            existing.last_used_at = utcnow()
            return
        session.add(TranslationCache(
            cache_key=key,
            source_hash=sha256_text(sentence.original_text),
            context_hash=context_hash,
            model_key=f"{client.provider.id}:{client.model.id}",
            prompt_version=prompt_version,
            params_json=params,
            translated_text=text,
        ))

    async def _save_ai_translation(
        self,
        session: AsyncSession,
        sentence: Sentence,
        text: str,
        *,
        client: ResolvedClient,
        prompt_version: int,
        cache_key: str | None,
        title: str,
    ) -> str:
        text = text.strip()
        existing = await session.scalar(
            select(Translation).where(Translation.sentence_id == sentence.id)
        )
        now = utcnow()
        if existing is not None and existing.origin == "manual":
            if existing.text.strip() == text:
                sentence.translation_state = "completed"
                sentence.translation_error = None
                return "unchanged"
            pending = await session.scalar(
                select(TranslationReview).where(
                    TranslationReview.translation_id == existing.id,
                    TranslationReview.status == "pending",
                ).order_by(TranslationReview.created_at.desc())
            )
            if pending is not None:
                pending.candidate_text = text
                pending.model_name = client.model.name
                pending.prompt_version = prompt_version
                pending.cache_key = cache_key
            else:
                session.add(TranslationReview(
                    translation_id=existing.id,
                    sentence_id=sentence.id,
                    candidate_text=text,
                    previous_text=existing.text,
                    reason="manual_conflict",
                    model_name=client.model.name,
                    prompt_version=prompt_version,
                    cache_key=cache_key,
                ))
            sentence.translation_state = "completed"
            sentence.translation_error = None
            return "review"

        if existing is not None:
            if existing.text.strip() == text:
                existing.model_name = client.model.name
                existing.provider_name = client.provider.name
                existing.prompt_version = prompt_version
                existing.cache_key = cache_key
                sentence.translation_state = "completed"
                sentence.translation_error = None
                sentence.translated_at = now
                return "unchanged"
            session.add(TranslationVersion(
                translation_id=existing.id,
                sentence_id=sentence.id,
                text=existing.text,
                origin=existing.origin,
                model_name=existing.model_name,
                prompt_version=existing.prompt_version,
                note="replaced by AI translation",
            ))
            existing.text = text
            existing.origin = "ai"
            existing.status = "completed"
            existing.model_name = client.model.name
            existing.provider_name = client.provider.name
            existing.prompt_version = prompt_version
            existing.cache_key = cache_key
            existing.edited_at = None
            existing.version += 1
            sentence.translation_state = "completed"
            sentence.translation_error = None
            sentence.translated_at = now
            await index_sentence(
                session,
                sentence_id=sentence.id,
                book_id=sentence.book_id,
                chapter_id=sentence.chapter_id,
                title=title,
                original_text=sentence.original_text,
                translated_text=text,
            )
            return "saved"

        translation = Translation(
            sentence_id=sentence.id,
            paragraph_id=sentence.paragraph_id,
            chapter_id=sentence.chapter_id,
            book_id=sentence.book_id,
            text=text,
            origin="ai",
            status="completed",
            model_name=client.model.name,
            provider_name=client.provider.name,
            prompt_version=prompt_version,
            source_hash=sha256_text(sentence.original_text),
            cache_key=cache_key,
        )
        session.add(translation)
        sentence.translation_state = "completed"
        sentence.translation_error = None
        sentence.translated_at = now
        await session.flush()
        await index_sentence(
            session,
            sentence_id=sentence.id,
            book_id=sentence.book_id,
            chapter_id=sentence.chapter_id,
            title=title,
            original_text=sentence.original_text,
            translated_text=text,
        )
        return "created"

    async def _reset_pending_states(
        self, session: AsyncSession, targets: list[Sentence], existing_translations: dict
    ) -> None:
        for sentence in targets:
            if sentence.translation_state in {"queued", "translating"}:
                sentence.translation_state = (
                    "completed" if sentence.id in existing_translations else "pending"
                )
        await session.commit()

    async def refresh_counts(
        self, session: AsyncSession, book_id: str, chapter_id: str | None = None
    ) -> None:
        book_count = await session.scalar(
            select(func.count()).select_from(Translation).where(Translation.book_id == book_id)
        ) or 0
        book = await session.get(Book, book_id)
        if book is not None:
            book.translated_sentence_count = book_count
        if chapter_id:
            chapter_count = await session.scalar(
                select(func.count()).select_from(Translation).where(
                    Translation.chapter_id == chapter_id
                )
            ) or 0
            chapter = await session.get(Chapter, chapter_id)
            if chapter is not None:
                chapter.translated_count = chapter_count
        await session.flush()

    # ------------------------------------------------------------------ manual editing
    async def edit_translation(
        self, session: AsyncSession, translation_id: str, text: str, note: str | None = None
    ) -> Translation:
        translation = await session.get(Translation, translation_id)
        if translation is None:
            raise not_found("Translation", translation_id)
        if not text.strip():
            raise AppError(ErrorCode.VALIDATION_ERROR, "Translation text cannot be empty", status_code=422)
        sentence = await session.get(Sentence, translation.sentence_id)
        if sentence is None:
            raise not_found("Sentence", translation.sentence_id)
        if translation.text != text.strip():
            session.add(TranslationVersion(
                translation_id=translation.id,
                sentence_id=sentence.id,
                text=translation.text,
                origin=translation.origin,
                model_name=translation.model_name,
                prompt_version=translation.prompt_version,
                note=note or "manual edit",
            ))
        translation.text = text.strip()
        translation.origin = "manual"
        translation.status = "completed"
        translation.edited_at = utcnow()
        translation.version += 1
        sentence.translation_state = "completed"
        sentence.translation_error = None
        sentence.translated_at = utcnow()
        pending_reviews = list((await session.scalars(
            select(TranslationReview).where(
                TranslationReview.translation_id == translation.id,
                TranslationReview.status == "pending",
            )
        )).all())
        for review in pending_reviews:
            review.status = "rejected"
            review.resolved_at = utcnow()
        await self._reindex(session, translation)
        await self.refresh_counts(session, translation.book_id, translation.chapter_id)
        await session.commit()
        await session.refresh(translation)
        return translation

    async def create_manual_translation(
        self, session: AsyncSession, sentence_id: str, text: str
    ) -> Translation:
        sentence = await session.get(Sentence, sentence_id)
        if sentence is None:
            raise not_found("Sentence", sentence_id)
        if not text.strip():
            raise AppError(ErrorCode.VALIDATION_ERROR, "Translation text cannot be empty", status_code=422)
        existing = await session.scalar(
            select(Translation).where(Translation.sentence_id == sentence_id)
        )
        if existing is not None:
            raise AppError(
                ErrorCode.CONFLICT, "Translation already exists; edit it instead",
                status_code=409, details={"translation_id": existing.id},
            )
        translation = Translation(
            sentence_id=sentence.id,
            paragraph_id=sentence.paragraph_id,
            chapter_id=sentence.chapter_id,
            book_id=sentence.book_id,
            text=text.strip(),
            origin="manual",
            status="completed",
            model_name="manual",
            edited_at=utcnow(),
        )
        session.add(translation)
        sentence.translation_state = "completed"
        sentence.translation_error = None
        sentence.translated_at = utcnow()
        await session.flush()
        await self._reindex(session, translation)
        await self.refresh_counts(session, translation.book_id, translation.chapter_id)
        await session.commit()
        await session.refresh(translation)
        return translation

    async def _reindex(self, session: AsyncSession, translation: Translation) -> None:
        sentence = await session.get(Sentence, translation.sentence_id)
        chapter = await session.get(Chapter, translation.chapter_id)
        book = await session.get(Book, translation.book_id)
        if sentence and chapter and book:
            await index_sentence(
                session,
                sentence_id=sentence.id,
                book_id=book.id,
                chapter_id=chapter.id,
                title=f"{book.title} · {chapter.title}",
                original_text=sentence.original_text,
                translated_text=translation.text,
            )

    # ------------------------------------------------------------------ reviews
    async def list_reviews(
        self, session: AsyncSession, *, status: str = "pending", limit: int = 100
    ) -> list[dict[str, Any]]:
        rows = (await session.execute(
            select(TranslationReview, Sentence, Chapter, Book)
            .join(Sentence, Sentence.id == TranslationReview.sentence_id)
            .join(Chapter, Chapter.id == Sentence.chapter_id)
            .join(Book, Book.id == Sentence.book_id)
            .where(TranslationReview.status == status)
            .order_by(TranslationReview.created_at.desc())
            .limit(limit)
        )).all()
        return [
            {
                "id": review.id,
                "translation_id": review.translation_id,
                "sentence_id": review.sentence_id,
                "candidate_text": review.candidate_text,
                "previous_text": review.previous_text,
                "reason": review.reason,
                "status": review.status,
                "model_name": review.model_name,
                "prompt_version": review.prompt_version,
                "created_at": review.created_at,
                "book_id": book.id,
                "book_title": book.title,
                "chapter_id": chapter.id,
                "chapter_title": chapter.title,
                "original_text": sentence.original_text,
            }
            for review, sentence, chapter, book in rows
        ]

    async def resolve_review(
        self,
        session: AsyncSession,
        review_id: str,
        *,
        action: str,
        text: str | None = None,
    ) -> TranslationReview:
        review = await session.get(TranslationReview, review_id)
        if review is None:
            raise not_found("TranslationReview", review_id)
        if review.status != "pending":
            raise AppError(ErrorCode.CONFLICT, "Review already resolved", status_code=409)
        translation = await session.get(Translation, review.translation_id)
        if translation is None:
            raise not_found("Translation", review.translation_id)
        sentence = await session.get(Sentence, review.sentence_id)

        if action == "reject":
            review.status = "rejected"
            review.resolved_at = utcnow()
        elif action == "accept":
            chosen = (text or review.candidate_text).strip()
            if not chosen:
                raise AppError(ErrorCode.VALIDATION_ERROR, "Candidate translation is empty", status_code=422)
            session.add(TranslationVersion(
                translation_id=translation.id,
                sentence_id=translation.sentence_id,
                text=translation.text,
                origin=translation.origin,
                model_name=translation.model_name,
                prompt_version=translation.prompt_version,
                note="replaced by reviewed candidate",
            ))
            translation.text = chosen
            translation.origin = "manual" if text is not None else "ai"
            translation.status = "completed"
            translation.model_name = review.model_name
            translation.prompt_version = review.prompt_version
            translation.cache_key = review.cache_key
            translation.edited_at = utcnow() if text is not None else None
            translation.version += 1
            if sentence is not None:
                sentence.translation_state = "completed"
                sentence.translation_error = None
                sentence.translated_at = utcnow()
            review.status = "accepted"
            review.resolved_at = utcnow()
            for other in (await session.scalars(
                select(TranslationReview).where(
                    TranslationReview.translation_id == translation.id,
                    TranslationReview.status == "pending",
                    TranslationReview.id != review.id,
                )
            )).all():
                other.status = "rejected"
                other.resolved_at = utcnow()
            await self._reindex(session, translation)
        else:
            raise AppError(ErrorCode.VALIDATION_ERROR, "action must be accept or reject", status_code=422)

        await self.refresh_counts(session, translation.book_id, translation.chapter_id)
        await session.commit()
        await session.refresh(review)
        return review


def make_translation_handler(settings: Settings, adapter_factory: AdapterFactory | None = None):
    async def handler(session: AsyncSession, task: Task, ctx: TaskContext) -> dict[str, Any]:
        service = TranslationService(settings, adapter_factory=adapter_factory)
        return await service.run_task(session, task, ctx)

    return handler
