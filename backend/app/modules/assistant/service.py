"""AI reading assistant grounded in the current text and local knowledge base."""

from __future__ import annotations

from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.ai.json_utils import complete_json
from app.ai.prompts import get_active_prompt, render_prompt
from app.ai.providers import AIClientFactory, ChatMessage
from app.ai.providers.registry import AdapterFactory
from app.core.config import Settings
from app.core.errors import AppError, ErrorCode, not_found
from app.core.utils import iso, new_id, utcnow
from app.database.models import (
    AssistantMessage, AssistantSession, Book, Chapter, Paragraph, Sentence, Translation,
)
from app.modules.search.service import search_entities, search_events, search_text

MAX_CONTEXT_CHARS = 9000


class AssistantService:
    def __init__(self, settings: Settings, adapter_factory: AdapterFactory | None = None) -> None:
        self.settings = settings
        self.adapter_factory = adapter_factory

    async def chat(
        self,
        session: AsyncSession,
        *,
        question: str,
        book_id: str | None = None,
        chapter_id: str | None = None,
        paragraph_id: str | None = None,
        sentence_id: str | None = None,
        session_id: str | None = None,
        model_id: str | None = None,
    ) -> dict[str, Any]:
        question = question.strip()
        if not question:
            raise AppError(ErrorCode.VALIDATION_ERROR, "Question cannot be empty", status_code=422)
        factory = AIClientFactory(session, self.settings, adapter_factory=self.adapter_factory)
        client = await factory.resolve(model_id=model_id, purpose="chat")

        context, book, chapter, current_sources = await self._build_context(
            session, book_id=book_id, chapter_id=chapter_id,
            paragraph_id=paragraph_id, sentence_id=sentence_id,
        )
        if chapter is not None and book is None:
            book = await session.get(Book, chapter.book_id)

        knowledge_lines, local_sources = await self._knowledge_context(
            session, question, book_id=book.id if book else book_id
        )
        history = ""
        assistant_session: AssistantSession | None = None
        if session_id:
            assistant_session = await session.get(AssistantSession, session_id)
            if assistant_session is None:
                raise not_found("AssistantSession", session_id)
            messages = list((await session.scalars(
                select(AssistantMessage)
                .where(AssistantMessage.session_id == session_id)
                .order_by(AssistantMessage.created_at.desc())
                .limit(8)
            )).all())
            history = "\n".join(
                f"{'用户' if message.role == 'user' else '助手'}：{message.content[:1200]}"
                for message in reversed(messages)
            )

        prompt = await get_active_prompt(session, self.settings, "assistant")
        rendered = render_prompt(prompt.template, {
            "book_title": book.title if book else "（未选择书籍）",
            "author": (book.author or "未知") if book else "未知",
            "chapter_title": chapter.title if chapter else "（未选择章节）",
            "context": context or "（未提供当前文本）",
            "knowledge_context": "\n".join(knowledge_lines) or "（本地知识库无匹配资料）",
            "history": history or "（无）",
            "question": question,
        })
        data, result = await complete_json(
            client.adapter,
            [ChatMessage(role="user", content=rendered)],
            temperature=0.3,
            max_tokens=min(client.model.max_output_tokens, 3000),
            timeout=client.model.timeout_seconds,
        )
        if not isinstance(data, dict) or not isinstance(data.get("answer"), str) or not data["answer"].strip():
            raise AppError(
                ErrorCode.AI_INVALID_RESPONSE,
                "AI assistant returned an invalid answer payload",
                status_code=502,
            )
        citations = await self._verify_citations(session, data.get("citations") or [])
        claims = []
        for claim in data.get("claims") or []:
            if not isinstance(claim, dict) or not claim.get("text"):
                continue
            kind = str(claim.get("kind") or "unverified")
            if kind not in {"explicit", "inference", "analysis", "unverified"}:
                kind = "unverified"
            claims.append({"text": str(claim["text"]), "kind": kind})

        if assistant_session is None:
            assistant_session = AssistantSession(
                id=new_id(),
                title=question[:80],
                book_id=book.id if book else book_id,
                chapter_id=chapter.id if chapter else chapter_id,
            )
            session.add(assistant_session)
            await session.flush()
        else:
            assistant_session.updated_at = utcnow()
            if book_id:
                assistant_session.book_id = book_id
            if chapter_id:
                assistant_session.chapter_id = chapter_id

        user_message = AssistantMessage(
            id=new_id(), session_id=assistant_session.id, role="user", content=question
        )
        answer_message = AssistantMessage(
            id=new_id(),
            session_id=assistant_session.id,
            role="assistant",
            content=data["answer"].strip(),
            citations=citations,
            model_name=client.model.name,
        )
        session.add_all([user_message, answer_message])
        await session.commit()
        await session.refresh(answer_message)
        return {
            "session_id": assistant_session.id,
            "message_id": answer_message.id,
            "answer": answer_message.content,
            "citations": citations,
            "claims": claims,
            "local_sources": local_sources,
            "model": client.model.name,
            "prompt_version": prompt.version,
            "created_at": iso(answer_message.created_at),
        }

    async def _build_context(
        self,
        session: AsyncSession,
        *,
        book_id: str | None,
        chapter_id: str | None,
        paragraph_id: str | None,
        sentence_id: str | None,
    ) -> tuple[str, Book | None, Chapter | None, list[dict[str, Any]]]:
        book = await session.get(Book, book_id) if book_id else None
        if book is not None and book.deleted_at is not None:
            raise not_found("Book", book_id)
        chapter = await session.get(Chapter, chapter_id) if chapter_id else None
        if chapter is not None:
            if chapter.book_id != (book_id or chapter.book_id):
                raise AppError(ErrorCode.VALIDATION_ERROR, "Chapter does not belong to this book", status_code=422)
            if book is None:
                book = await session.get(Book, chapter.book_id)
        if sentence_id:
            sentence = await session.get(Sentence, sentence_id)
            if sentence is None:
                raise not_found("Sentence", sentence_id)
            paragraph = await session.get(Paragraph, sentence.paragraph_id)
            chapter = await session.get(Chapter, sentence.chapter_id)
            book = await session.get(Book, sentence.book_id)
            if paragraph is None:
                raise not_found("Paragraph", sentence.paragraph_id)
            paragraphs = list((await session.scalars(
                select(Paragraph).where(
                    Paragraph.chapter_id == paragraph.chapter_id,
                    Paragraph.ordinal.between(max(0, paragraph.ordinal - 1), paragraph.ordinal + 1),
                ).order_by(Paragraph.ordinal)
            )).all())
            context, sources = await self._paragraphs_context(
                session, paragraphs, focus_sentence_id=sentence.id
            )
            return context, book, chapter, sources
        if paragraph_id:
            paragraph = await session.get(Paragraph, paragraph_id)
            if paragraph is None:
                raise not_found("Paragraph", paragraph_id)
            chapter = await session.get(Chapter, paragraph.chapter_id)
            book = await session.get(Book, paragraph.book_id)
            paragraphs = list((await session.scalars(
                select(Paragraph).where(
                    Paragraph.chapter_id == paragraph.chapter_id,
                    Paragraph.ordinal.between(max(0, paragraph.ordinal - 1), paragraph.ordinal + 1),
                ).order_by(Paragraph.ordinal)
            )).all())
            context, sources = await self._paragraphs_context(session, paragraphs)
            return context, book, chapter, sources
        if chapter is not None:
            paragraphs = list((await session.scalars(
                select(Paragraph).where(Paragraph.chapter_id == chapter.id)
                .order_by(Paragraph.ordinal).limit(20)
            )).all())
            context, sources = await self._paragraphs_context(session, paragraphs)
            return context, book, chapter, sources
        if book is not None:
            return (
                f"《{book.title}》\n作者：{book.author or '未知'}\n朝代：{book.dynasty or '未知'}\n"
                f"简介：{book.description or '（无）'}",
                book, None, [],
            )
        return "", None, None, []

    async def _paragraphs_context(
        self,
        session: AsyncSession,
        paragraphs: list[Paragraph],
        *,
        focus_sentence_id: str | None = None,
    ) -> tuple[str, list[dict[str, Any]]]:
        if not paragraphs:
            return "", []
        paragraph_ids = [paragraph.id for paragraph in paragraphs]
        sentences = list((await session.scalars(
            select(Sentence).where(Sentence.paragraph_id.in_(paragraph_ids))
            .order_by(Sentence.ordinal)
        )).all())
        translations = {
            row.sentence_id: row.text for row in (await session.scalars(
                select(Translation).where(Translation.sentence_id.in_([s.id for s in sentences]))
            )).all()
        } if sentences else {}
        lines: list[str] = []
        sources: list[dict[str, Any]] = []
        total = 0
        for paragraph in paragraphs:
            lines.append(f"\n【第 {paragraph.ordinal + 1} 段】")
            paragraph_sentences = [s for s in sentences if s.paragraph_id == paragraph.id]
            for sentence in paragraph_sentences:
                prefix = "▶ " if focus_sentence_id == sentence.id else ""
                lines.append(f"{prefix}[句 {sentence.id}] 原文：{sentence.original_text}")
                if sentence.id in translations:
                    lines.append(f"译文：{translations[sentence.id]}")
                sources.append({
                    "sentence_id": sentence.id,
                    "quote": sentence.original_text,
                    "translation": translations.get(sentence.id),
                    "focus": focus_sentence_id == sentence.id,
                })
                total += len(sentence.original_text)
                if total > MAX_CONTEXT_CHARS:
                    break
            if total > MAX_CONTEXT_CHARS:
                lines.append("（上下文过长，已截断）")
                break
        return "\n".join(lines), sources

    async def _knowledge_context(
        self, session: AsyncSession, question: str, *, book_id: str | None
    ) -> tuple[list[str], list[dict[str, Any]]]:
        import re as _re

        search_query = _re.sub(
            r"(是谁|是什么|什么|如何|为什么|为何|怎样|怎么|请问|介绍一下|介绍|有关|关于|"
            r"[？?！!。，,；;：:\s]|的|吗|呢|吧|啊)",
            " ",
            question,
        ).strip()
        if not search_query:
            search_query = question[:20]
        lines: list[str] = []
        sources: list[dict[str, Any]] = []
        try:
            text_hits = await search_text(session, search_query, book_id=book_id, limit=8)
        except Exception:
            text_hits = []
        for hit in text_hits:
            lines.append(
                f"《{hit['book_title']}》{hit['chapter_title'] or ''} "
                f"[句 {hit['sentence_id']}]：{hit['original_text']}"
            )
            sources.append({
                "type": "text",
                "book_title": hit["book_title"],
                "chapter_title": hit.get("chapter_title"),
                "sentence_id": hit["sentence_id"],
                "quote": hit["original_text"],
                "translation": hit.get("translation_text"),
            })
        try:
            entities = await search_entities(session, search_query, limit=6)
        except Exception:
            entities = []
        for entity in entities:
            lines.append(
                f"人物/实体：{entity['canonical_name']}（{entity['kind']}，{entity['dynasty'] or '朝代未知'}）"
                f"{'：' + entity['summary'] if entity.get('summary') else ''}"
            )
            sources.append({"type": "entity", "entity_id": entity["id"], "name": entity["canonical_name"]})
        try:
            events = await search_events(session, search_query, limit=6)
        except Exception:
            events = []
        for event in events:
            lines.append(
                f"历史事件：{event['name']}（{event.get('time_raw') or '时间未知'}，{event['event_type']}）"
            )
            sources.append({"type": "event", "event_id": event["id"], "name": event["name"]})
        return lines, sources

    async def _verify_citations(
        self, session: AsyncSession, citations: list[Any]
    ) -> list[dict[str, Any]]:
        verified: list[dict[str, Any]] = []
        for citation in citations[:20]:
            if not isinstance(citation, dict):
                continue
            item = {
                "book": str(citation.get("book") or "")[:300],
                "chapter": str(citation.get("chapter") or "")[:300],
                "sentence_id": citation.get("sentence_id"),
                "quote": str(citation.get("quote") or "")[:1000],
                "note": str(citation.get("note") or "")[:500],
                "verified": False,
            }
            if item["sentence_id"]:
                sentence = await session.get(Sentence, str(item["sentence_id"]))
                if sentence is not None:
                    quote = item["quote"].strip()
                    item["verified"] = bool(quote) and quote[:30] in sentence.original_text
                    if not item["quote"]:
                        item["quote"] = sentence.original_text[:1000]
                    if not item["book"]:
                        book = await session.get(Book, sentence.book_id)
                        item["book"] = book.title if book else ""
                    if not item["chapter"]:
                        chapter = await session.get(Chapter, sentence.chapter_id)
                        item["chapter"] = chapter.title if chapter else ""
            verified.append(item)
        return verified
