"""Context windows and cache keys for translation.

A translation cache key covers source text, the paragraph's surrounding context,
model/provider identity, prompt version and generation parameters. Two different
contexts therefore never share a translation by accident.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field

from app.core.utils import sha256_text

CONTEXT_LIMIT = 1200


@dataclass
class ParagraphContext:
    paragraph_id: str
    before: str
    after: str
    context_hash: str


@dataclass
class TargetSentence:
    id: str
    text: str
    paragraph_id: str
    start_offset: int
    end_offset: int


@dataclass
class BatchChunk:
    items: list[TargetSentence]
    context_before: str
    context_after: str


@dataclass
class TranslationBatch:
    items: list[TargetSentence] = field(default_factory=list)
    context_before: str = ""
    context_after: str = ""


def build_paragraph_contexts(
    paragraphs: list,
    *,
    context_limit: int = CONTEXT_LIMIT,
) -> dict[str, ParagraphContext]:
    contexts: dict[str, ParagraphContext] = {}
    for index, paragraph in enumerate(paragraphs):
        before = ""
        after = ""
        if index > 0:
            before = paragraphs[index - 1].original_text[-context_limit:]
        if index + 1 < len(paragraphs):
            after = paragraphs[index + 1].original_text[:context_limit]
        own = paragraph.original_text[:context_limit]
        raw = f"{paragraph.id}|{before}|{own}|{after}"
        contexts[paragraph.id] = ParagraphContext(
            paragraph_id=paragraph.id,
            before=before,
            after=after,
            context_hash=sha256_text(raw),
        )
    return contexts


def translation_cache_key(
    *,
    source_text: str,
    context_hash: str,
    provider_id: str,
    model_id: str,
    prompt_version: int,
    params: dict,
) -> str:
    payload = json.dumps(
        {
            "source": sha256_text(source_text),
            "context": context_hash,
            "provider": provider_id,
            "model": model_id,
            "prompt_version": prompt_version,
            "params": params,
        },
        ensure_ascii=False,
        sort_keys=True,
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _chunk_context(
    paragraph, paragraph_sentences: list[TargetSentence], items: list[TargetSentence],
    context_chars: int,
) -> tuple[str, str]:
    first = items[0]
    last = items[-1]
    prefix_end = max(0, first.start_offset - paragraph.start_offset - 300)
    prefix = paragraph.original_text[prefix_end: first.start_offset - paragraph.start_offset]
    suffix_start = max(0, last.end_offset - paragraph.start_offset)
    suffix = paragraph.original_text[suffix_start: suffix_start + 300]
    before = prefix[-context_chars:] if prefix else ""
    after = suffix[:context_chars] if suffix else ""
    return before, after


def build_batches(
    targets: list[TargetSentence],
    *,
    paragraphs: list,
    max_chars: int,
    context_chars: int,
    max_items: int = 24,
) -> list[TranslationBatch]:
    paragraph_by_id = {paragraph.id: paragraph for paragraph in paragraphs}
    order = {paragraph.id: index for index, paragraph in enumerate(paragraphs)}
    grouped: dict[str, list[TargetSentence]] = {}
    for target in targets:
        grouped.setdefault(target.paragraph_id, []).append(target)

    chunks: list[BatchChunk] = []
    for paragraph_id in sorted(grouped, key=lambda pid: order.get(pid, 0)):
        paragraph = paragraph_by_id.get(paragraph_id)
        if paragraph is None:
            continue
        items = sorted(grouped[paragraph_id], key=lambda item: item.start_offset)
        current: list[TargetSentence] = []
        current_chars = 0
        for item in items:
            if current and (current_chars + len(item.text) > max_chars or len(current) >= 12):
                before, after = _chunk_context(paragraph, items, current, context_chars)
                chunks.append(BatchChunk(current, before, after))
                current = []
                current_chars = 0
            current.append(item)
            current_chars += len(item.text)
        if current:
            before, after = _chunk_context(paragraph, items, current, context_chars)
            chunks.append(BatchChunk(current, before, after))

    batches: list[TranslationBatch] = []
    current_batch: TranslationBatch | None = None
    current_chars = 0
    for chunk in chunks:
        chunk_chars = sum(len(item.text) for item in chunk.items)
        if current_batch and (
            current_chars + chunk_chars > max_chars
            or len(current_batch.items) + len(chunk.items) > max_items
        ):
            batches.append(current_batch)
            current_batch = None
            current_chars = 0
        if current_batch is None:
            current_batch = TranslationBatch(
                items=list(chunk.items),
                context_before=chunk.context_before,
                context_after=chunk.context_after,
            )
            current_chars = chunk_chars
        else:
            current_batch.items.extend(chunk.items)
            current_batch.context_after = chunk.context_after
            current_chars += chunk_chars
    if current_batch and current_batch.items:
        batches.append(current_batch)
    return batches
