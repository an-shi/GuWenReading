"""Pydantic request/response models shared across API modules."""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class BookUpdate(StrictModel):
    title: str | None = Field(default=None, min_length=1, max_length=300)
    author: str | None = Field(default=None, max_length=200)
    dynasty: str | None = Field(default=None, max_length=100)
    category: str | None = Field(default=None, max_length=100)
    description: str | None = None
    tags: list[str] | None = None


class TranslationEdit(StrictModel):
    text: str = Field(min_length=1)
    note: str | None = Field(default=None, max_length=300)


class ManualTranslation(StrictModel):
    text: str = Field(min_length=1)


class ReviewResolve(StrictModel):
    action: Literal["accept", "reject"]
    text: str | None = None


class TranslateChapterRequest(StrictModel):
    model_id: str | None = None
    retranslate: bool = False
    only_failed: bool = False


class TranslateSentenceRequest(StrictModel):
    model_id: str | None = None
    retranslate: bool = False


class ReadingProgressUpdate(StrictModel):
    book_id: str
    device_id: str = "local"
    chapter_id: str | None = None
    paragraph_id: str | None = None
    sentence_id: str | None = None
    position_ratio: float = Field(default=0.0, ge=0.0, le=1.0)


class AnnotationCreate(StrictModel):
    book_id: str
    chapter_id: str | None = None
    paragraph_id: str | None = None
    sentence_id: str | None = None
    quote: str | None = None
    content: str = Field(min_length=1)
    color: str = "amber"
    tags: list[str] = Field(default_factory=list)
    device_id: str | None = None


class AnnotationUpdate(StrictModel):
    content: str | None = Field(default=None, min_length=1)
    color: str | None = None
    tags: list[str] | None = None


class BookmarkCreate(StrictModel):
    book_id: str
    chapter_id: str
    paragraph_id: str | None = None
    sentence_id: str | None = None
    label: str | None = None
    position_ratio: float = Field(default=0.0, ge=0.0, le=1.0)
    device_id: str | None = None


class ProviderCreate(StrictModel):
    name: str = Field(min_length=1, max_length=100)
    kind: Literal["openai_compatible", "openai", "ollama"] = "openai_compatible"
    base_url: str = Field(min_length=4, max_length=500)
    api_key: str | None = None
    headers: dict[str, str] = Field(default_factory=dict)
    enabled: bool = True
    notes: str | None = None


class ProviderUpdate(StrictModel):
    name: str | None = None
    kind: Literal["openai_compatible", "openai", "ollama"] | None = None
    base_url: str | None = None
    api_key: str | None = None
    clear_api_key: bool = False
    headers: dict[str, str] | None = None
    enabled: bool | None = None
    notes: str | None = None


class ProviderTestRequest(StrictModel):
    model_name: str | None = None


class ModelCreate(StrictModel):
    provider_id: str
    name: str = Field(min_length=1, max_length=200)
    display_name: str = Field(min_length=1, max_length=200)
    context_window: int = Field(default=8192, ge=512, le=2_000_000)
    max_output_tokens: int = Field(default=2048, ge=64, le=200_000)
    timeout_seconds: int = Field(default=120, ge=5, le=1800)
    max_concurrency: int = Field(default=2, ge=1, le=64)
    supports_streaming: bool = False
    supports_json: bool = True
    capabilities: list[str] = Field(default_factory=lambda: ["translation", "chat"])
    params: dict[str, Any] = Field(default_factory=dict)
    enabled: bool = True
    is_default_translation: bool = False
    is_default_chat: bool = False


class ModelUpdate(StrictModel):
    name: str | None = None
    display_name: str | None = None
    context_window: int | None = Field(default=None, ge=512, le=2_000_000)
    max_output_tokens: int | None = Field(default=None, ge=64, le=200_000)
    timeout_seconds: int | None = Field(default=None, ge=5, le=1800)
    max_concurrency: int | None = Field(default=None, ge=1, le=64)
    supports_streaming: bool | None = None
    supports_json: bool | None = None
    capabilities: list[str] | None = None
    params: dict[str, Any] | None = None
    enabled: bool | None = None
    is_default_translation: bool | None = None
    is_default_chat: bool | None = None


class PromptVersionCreate(StrictModel):
    name: str = Field(min_length=1, max_length=200)
    template: str = Field(min_length=10)
    variables: list[str] = Field(default_factory=list)
    description: str | None = None


class LoginRequest(StrictModel):
    username: str = Field(min_length=2, max_length=100)
    password: str = Field(min_length=8, max_length=200)


class RegisterRequest(LoginRequest):
    display_name: str | None = None


class DeviceRegister(StrictModel):
    name: str = Field(min_length=1, max_length=200)
    platform: Literal["windows", "android", "ios", "web", "server", "other"] = "other"
    fingerprint: str | None = Field(default=None, max_length=200)
    app_version: str | None = None


class AssistantChatRequest(StrictModel):
    question: str = Field(min_length=1, max_length=4000)
    book_id: str | None = None
    chapter_id: str | None = None
    paragraph_id: str | None = None
    sentence_id: str | None = None
    session_id: str | None = None
    model_id: str | None = None


class ExtractionRequest(StrictModel):
    chapter_id: str
    model_id: str | None = None
    extract_entities: bool = True
    extract_relations: bool = True
    extract_events: bool = True


class EntityCreate(StrictModel):
    canonical_name: str = Field(min_length=1, max_length=200)
    kind: str = "person"
    dynasty: str | None = None
    courtesy_name: str | None = None
    art_name: str | None = None
    posthumous_name: str | None = None
    temple_name: str | None = None
    aliases: list[str] = Field(default_factory=list)
    birth_raw: str | None = None
    death_raw: str | None = None
    birth_year: int | None = None
    death_year: int | None = None
    identity: str | None = None
    offices: list[str] = Field(default_factory=list)
    summary: str | None = None
    status: Literal["confirmed", "pending", "rejected"] = "pending"


class EntityUpdate(StrictModel):
    canonical_name: str | None = None
    kind: str | None = None
    dynasty: str | None = None
    courtesy_name: str | None = None
    art_name: str | None = None
    posthumous_name: str | None = None
    temple_name: str | None = None
    aliases: list[str] | None = None
    birth_raw: str | None = None
    death_raw: str | None = None
    birth_year: int | None = None
    death_year: int | None = None
    identity: str | None = None
    offices: list[str] | None = None
    summary: str | None = None
    status: Literal["confirmed", "pending", "rejected"] | None = None


class MergeRequest(StrictModel):
    source_entity_ids: list[str] = Field(min_length=1)


class RelationCreate(StrictModel):
    source_entity_id: str
    target_entity_id: str
    relation_type: str
    label: str | None = None
    description: str | None = None
    status: Literal["explicit", "inferred", "confirmed", "rejected"] = "confirmed"
    confidence: float | None = Field(default=None, ge=0, le=1)
    evidence: list[dict[str, Any]] = Field(default_factory=list)


class EventCreate(StrictModel):
    name: str = Field(min_length=1, max_length=300)
    event_type: str = "other"
    description: str | None = None
    dynasty: str | None = None
    time_raw: str | None = None
    era_name: str | None = None
    reign_year: str | None = None
    ganzhi: str | None = None
    time_start_year: int | None = None
    time_end_year: int | None = None
    time_precision: Literal["exact", "day", "month", "year", "range", "circa", "unknown"] | None = None
    status: Literal["extracted", "confirmed", "rejected"] = "confirmed"
    confidence: float | None = Field(default=None, ge=0, le=1)
    participant_entity_ids: list[str] = Field(default_factory=list)
    evidence: list[dict[str, Any]] = Field(default_factory=list)


class EventUpdate(StrictModel):
    name: str | None = None
    event_type: str | None = None
    description: str | None = None
    dynasty: str | None = None
    time_raw: str | None = None
    era_name: str | None = None
    reign_year: str | None = None
    ganzhi: str | None = None
    time_start_year: int | None = None
    time_end_year: int | None = None
    time_precision: str | None = None
    status: Literal["extracted", "confirmed", "rejected"] | None = None
    confidence: float | None = Field(default=None, ge=0, le=1)


class SearchQuery(StrictModel):
    q: str = Field(min_length=1, max_length=200)
    scope: Literal["all", "original", "translation"] = "all"
    book_id: str | None = None
    limit: int = Field(default=20, ge=1, le=100)


class SyncOperationInput(StrictModel):
    entity_type: str
    entity_id: str
    operation: Literal["upsert", "delete"]
    base_version: int = 0
    version: int = 1
    updated_at: str | None = None
    data: dict[str, Any] = Field(default_factory=dict)


class SyncPushRequest(StrictModel):
    device_id: str
    operations: list[SyncOperationInput] = Field(default_factory=list, max_length=500)


class SyncPullQuery(StrictModel):
    device_id: str
    after: int = 0
    limit: int = Field(default=200, ge=1, le=1000)
