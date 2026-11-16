"""AI provider, model and prompt management.

API keys are write-only from the client's perspective: responses expose only a
masked hint and a boolean.
"""

from __future__ import annotations

from urllib.parse import urlparse

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.ai.prompts import create_prompt_version, get_active_prompt, list_prompts
from app.ai.providers import AIClientFactory, AIProviderError
from app.api.deps import get_session, require_auth
from app.api.v1.schemas import (
    ModelCreate, ModelUpdate, PromptVersionCreate, ProviderCreate, ProviderTestRequest,
    ProviderUpdate,
)
from app.api.v1.serializers import serialize_model, serialize_provider
from app.core.errors import AppError, ErrorCode
from app.core.responses import ok
from app.core.utils import iso, new_id, utcnow
from app.database.models import AIModel, AIProvider, PromptTemplate

router = APIRouter(tags=["ai"], dependencies=[Depends(require_auth)])


def _validate_base_url(value: str) -> str:
    value = value.strip()
    parsed = urlparse(value)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise AppError(
            ErrorCode.VALIDATION_ERROR,
            "Base URL must be a valid http(s) URL, e.g. https://api.openai.com/v1",
            status_code=422,
        )
    return value.rstrip("/")


@router.get("/ai/providers")
async def get_providers(session: AsyncSession = Depends(get_session)):
    rows = list((await session.scalars(
        select(AIProvider).where(AIProvider.deleted_at.is_(None)).order_by(AIProvider.created_at)
    )).all())
    return ok([serialize_provider(provider) for provider in rows])


@router.post("/ai/providers", status_code=201)
async def create_provider(
    body: ProviderCreate,
    request: Request,
    session: AsyncSession = Depends(get_session),
):
    vault = request.app.state.security.vault
    provider = AIProvider(
        id=new_id(),
        name=body.name.strip(),
        kind=body.kind,
        base_url=_validate_base_url(body.base_url),
        api_key_encrypted=vault.encrypt(body.api_key) if body.api_key else None,
        api_key_hint=("****" + body.api_key[-4:]) if body.api_key and len(body.api_key) > 8 else None,
        headers=body.headers,
        enabled=body.enabled,
        notes=body.notes,
    )
    session.add(provider)
    await session.commit()
    await session.refresh(provider)
    return ok(serialize_provider(provider))


@router.put("/ai/providers/{provider_id}")
async def edit_provider(
    provider_id: str,
    body: ProviderUpdate,
    request: Request,
    session: AsyncSession = Depends(get_session),
):
    provider = await session.get(AIProvider, provider_id)
    if provider is None or provider.deleted_at is not None:
        raise AppError(ErrorCode.PROVIDER_NOT_FOUND, "AI provider not found", status_code=404)
    vault = request.app.state.security.vault
    if body.name is not None:
        provider.name = body.name.strip()
    if body.kind is not None:
        provider.kind = body.kind
    if body.base_url is not None:
        provider.base_url = _validate_base_url(body.base_url)
    if body.clear_api_key:
        provider.api_key_encrypted = None
        provider.api_key_hint = None
    elif body.api_key:
        provider.api_key_encrypted = vault.encrypt(body.api_key)
        provider.api_key_hint = "****" + body.api_key[-4:] if len(body.api_key) > 8 else None
    if body.headers is not None:
        provider.headers = body.headers
    if body.enabled is not None:
        provider.enabled = body.enabled
    if body.notes is not None:
        provider.notes = body.notes
    provider.version += 1
    provider.updated_at = utcnow()
    await session.commit()
    await session.refresh(provider)
    return ok(serialize_provider(provider))


@router.delete("/ai/providers/{provider_id}")
async def delete_provider(provider_id: str, session: AsyncSession = Depends(get_session)):
    provider = await session.get(AIProvider, provider_id)
    if provider is None or provider.deleted_at is not None:
        raise AppError(ErrorCode.PROVIDER_NOT_FOUND, "AI provider not found", status_code=404)
    provider.deleted_at = utcnow()
    provider.enabled = False
    provider.version += 1
    await session.execute(
        update(AIModel).where(AIModel.provider_id == provider_id).values(enabled=False)
    )
    await session.commit()
    return ok({"id": provider_id, "removed": True})


@router.post("/ai/providers/{provider_id}/test")
async def test_provider(
    provider_id: str,
    body: ProviderTestRequest,
    request: Request,
    session: AsyncSession = Depends(get_session),
):
    factory = AIClientFactory(
        session, request.app.state.settings, adapter_factory=request.app.state.adapter_factory
    )
    try:
        client = await factory.resolve_for_test(provider_id, model_name=body.model_name)
        result = await client.adapter.test(timeout=45)
    except AIProviderError as exc:
        raise AppError(
            ErrorCode.PROVIDER_ERROR,
            exc.message,
            status_code=502,
        ) from exc
    except AppError:
        raise
    except Exception as exc:
        raise AppError(
            ErrorCode.PROVIDER_ERROR,
            f"Provider test failed: {exc}",
            status_code=502,
        ) from exc
    return ok({
        **result,
        "provider_id": provider_id,
        "provider_name": client.provider.name,
    })


@router.get("/ai/models")
async def get_models(
    provider_id: str | None = Query(default=None),
    capability: str | None = Query(default=None),
    session: AsyncSession = Depends(get_session),
):
    statement = select(AIModel).where(AIModel.deleted_at.is_(None))
    if provider_id:
        statement = statement.where(AIModel.provider_id == provider_id)
    rows = list((await session.scalars(statement.order_by(AIModel.created_at))).all())
    if capability:
        rows = [row for row in rows if capability in (row.capabilities or [])]
    return ok([serialize_model(model) for model in rows])


@router.post("/ai/models", status_code=201)
async def create_model(
    body: ModelCreate,
    session: AsyncSession = Depends(get_session),
):
    provider = await session.get(AIProvider, body.provider_id)
    if provider is None or provider.deleted_at is not None:
        raise AppError(ErrorCode.PROVIDER_NOT_FOUND, "AI provider not found", status_code=404)
    if body.max_output_tokens > body.context_window:
        raise AppError(
            ErrorCode.VALIDATION_ERROR,
            "max_output_tokens cannot exceed context_window",
            status_code=422,
        )
    existing = await session.scalar(
        select(AIModel).where(
            AIModel.provider_id == body.provider_id, AIModel.name == body.name
        )
    )
    if existing is not None:
        raise AppError(ErrorCode.CONFLICT, "This model name already exists for the provider", status_code=409)
    if body.is_default_translation:
        await session.execute(update(AIModel).values(is_default_translation=False))
    if body.is_default_chat:
        await session.execute(update(AIModel).values(is_default_chat=False))
    model = AIModel(id=new_id(), **body.model_dump())
    session.add(model)
    await session.commit()
    await session.refresh(model)
    return ok(serialize_model(model))


@router.put("/ai/models/{model_id}")
async def edit_model(
    model_id: str,
    body: ModelUpdate,
    session: AsyncSession = Depends(get_session),
):
    model = await session.get(AIModel, model_id)
    if model is None or model.deleted_at is not None:
        raise AppError(ErrorCode.MODEL_NOT_FOUND, "AI model not found", status_code=404)
    values = body.model_dump(exclude_unset=True)
    if values.get("is_default_translation"):
        await session.execute(update(AIModel).values(is_default_translation=False))
    if values.get("is_default_chat"):
        await session.execute(update(AIModel).values(is_default_chat=False))
    for key, value in values.items():
        setattr(model, key, value)
    if model.max_output_tokens > model.context_window:
        raise AppError(
            ErrorCode.VALIDATION_ERROR,
            "max_output_tokens cannot exceed context_window",
            status_code=422,
        )
    model.version += 1
    model.updated_at = utcnow()
    await session.commit()
    await session.refresh(model)
    return ok(serialize_model(model))


@router.delete("/ai/models/{model_id}")
async def delete_model(model_id: str, session: AsyncSession = Depends(get_session)):
    model = await session.get(AIModel, model_id)
    if model is None or model.deleted_at is not None:
        raise AppError(ErrorCode.MODEL_NOT_FOUND, "AI model not found", status_code=404)
    model.deleted_at = utcnow()
    model.enabled = False
    model.is_default_translation = False
    model.is_default_chat = False
    model.version += 1
    await session.commit()
    return ok({"id": model_id, "removed": True})


@router.get("/ai/prompts")
async def get_prompts(session: AsyncSession = Depends(get_session)):
    rows = await list_prompts(session)
    return ok([
        {
            "id": row.id,
            "key": row.key,
            "version": row.version,
            "name": row.name,
            "description": row.description,
            "variables": row.variables or [],
            "is_active": row.is_active,
            "created_at": iso(row.created_at),
        }
        for row in rows
    ])


@router.get("/ai/prompts/{key}")
async def get_prompt_detail(
    key: str,
    request: Request,
    session: AsyncSession = Depends(get_session),
):
    active = await get_active_prompt(session, request.app.state.settings, key)
    versions = list((await session.scalars(
        select(PromptTemplate).where(PromptTemplate.key == key)
        .order_by(PromptTemplate.version.desc())
    )).all())
    return ok({
        "key": key,
        "active": {
            "version": active.version,
            "name": active.name,
            "template": active.template,
        },
        "versions": [
            {
                "id": row.id,
                "version": row.version,
                "name": row.name,
                "description": row.description,
                "variables": row.variables or [],
                "is_active": row.is_active,
                "created_at": iso(row.created_at),
            }
            for row in versions
        ],
    })


@router.post("/ai/prompts/{key}/versions", status_code=201)
async def add_prompt_version(
    key: str,
    body: PromptVersionCreate,
    session: AsyncSession = Depends(get_session),
):
    row = await create_prompt_version(
        session, key=key, name=body.name, template=body.template,
        variables=body.variables, description=body.description,
    )
    return ok({
        "id": row.id, "key": row.key, "version": row.version,
        "name": row.name, "is_active": row.is_active,
    })


@router.post("/ai/prompts/{key}/activate/{version}")
async def activate_prompt(
    key: str,
    version: int,
    session: AsyncSession = Depends(get_session),
):
    target = await session.scalar(
        select(PromptTemplate).where(PromptTemplate.key == key, PromptTemplate.version == version)
    )
    if target is None:
        raise AppError(ErrorCode.NOT_FOUND, "Prompt version not found", status_code=404)
    await session.execute(
        update(PromptTemplate).where(PromptTemplate.key == key).values(is_active=False)
    )
    target.is_active = True
    await session.commit()
    return ok({"key": key, "active_version": version})
