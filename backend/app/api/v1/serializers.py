"""Response serializers that never expose secrets."""

from __future__ import annotations

from typing import Any

from app.core.utils import iso
from app.database.models import AIProvider, AIModel, Book


def serialize_book(book: Book) -> dict[str, Any]:
    percent = (
        round(book.translated_sentence_count / book.sentence_count * 100, 2)
        if book.sentence_count else 0.0
    )
    return {
        "id": book.id,
        "title": book.title,
        "author": book.author,
        "dynasty": book.dynasty,
        "category": book.category,
        "description": book.description,
        "tags": book.tags or [],
        "source_format": book.source_format,
        "source_filename": book.source_filename,
        "file_size": book.file_size,
        "status": book.status,
        "cover_url": f"/api/v1/books/{book.id}/cover" if book.cover_path else None,
        "chapter_count": book.chapter_count,
        "paragraph_count": book.paragraph_count,
        "sentence_count": book.sentence_count,
        "translated_sentence_count": book.translated_sentence_count,
        "translation_percent": percent,
        "last_read_at": iso(book.last_read_at),
        "created_at": iso(book.created_at),
        "updated_at": iso(book.updated_at),
        "metadata": book.metadata_json or {},
        "version": book.version,
    }


def serialize_provider(provider: AIProvider) -> dict[str, Any]:
    return {
        "id": provider.id,
        "name": provider.name,
        "kind": provider.kind,
        "base_url": provider.base_url,
        "api_key_hint": provider.api_key_hint,
        "has_api_key": bool(provider.api_key_encrypted),
        "headers": provider.headers or {},
        "enabled": provider.enabled,
        "notes": provider.notes,
        "created_at": iso(provider.created_at),
        "updated_at": iso(provider.updated_at),
    }


def serialize_model(model: AIModel) -> dict[str, Any]:
    return {
        "id": model.id,
        "provider_id": model.provider_id,
        "name": model.name,
        "display_name": model.display_name,
        "context_window": model.context_window,
        "max_output_tokens": model.max_output_tokens,
        "timeout_seconds": model.timeout_seconds,
        "max_concurrency": model.max_concurrency,
        "supports_streaming": model.supports_streaming,
        "supports_json": model.supports_json,
        "capabilities": model.capabilities or [],
        "params": model.params or {},
        "enabled": model.enabled,
        "is_default_translation": model.is_default_translation,
        "is_default_chat": model.is_default_chat,
        "created_at": iso(model.created_at),
        "updated_at": iso(model.updated_at),
    }
