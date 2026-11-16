"""AI client resolution from persisted provider/model configuration."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.ai.providers.base import (
    AIProviderError, BaseChatAdapter, ModelConfig, ProviderConfig,
)
from app.ai.providers.ollama import OllamaAdapter
from app.ai.providers.openai_compat import OpenAICompatibleAdapter
from app.core.config import Settings
from app.core.errors import AppError, ErrorCode
from app.core.security import KeyVault
from app.database.models import AIModel, AIProvider


@dataclass
class ResolvedClient:
    provider: AIProvider
    model: AIModel
    adapter: BaseChatAdapter


AdapterFactory = Callable[[ProviderConfig, ModelConfig], BaseChatAdapter]


def build_adapter(provider: ProviderConfig, model: ModelConfig) -> BaseChatAdapter:
    if provider.kind in {"openai_compatible", "openai", "openai_compatible_server"}:
        return OpenAICompatibleAdapter(provider, model)
    if provider.kind == "ollama":
        return OllamaAdapter(provider, model)
    raise AIProviderError(f"Unsupported provider type: {provider.kind}")


class AIClientFactory:
    def __init__(
        self,
        session: AsyncSession,
        settings: Settings,
        vault: KeyVault | None = None,
        adapter_factory: AdapterFactory | None = None,
    ) -> None:
        self.session = session
        self.settings = settings
        self.vault = vault or KeyVault(settings)
        self.adapter_factory = adapter_factory or build_adapter

    def _provider_config(self, provider: AIProvider) -> ProviderConfig:
        return ProviderConfig(
            id=provider.id,
            name=provider.name,
            kind=provider.kind,
            base_url=provider.base_url,
            api_key=self.vault.decrypt(provider.api_key_encrypted),
            headers=dict(provider.headers or {}),
        )

    def _model_config(self, model: AIModel) -> ModelConfig:
        return ModelConfig(
            id=model.id,
            name=model.name,
            display_name=model.display_name,
            context_window=model.context_window,
            max_output_tokens=model.max_output_tokens,
            timeout_seconds=model.timeout_seconds,
            supports_json=model.supports_json,
            supports_streaming=model.supports_streaming,
            params=dict(model.params or {}),
        )

    async def resolve(
        self, *, model_id: str | None = None, purpose: str = "translation"
    ) -> ResolvedClient:
        model: AIModel | None = None
        provider: AIProvider | None = None

        if model_id:
            model = await self.session.get(AIModel, model_id)
            if model is None:
                raise AppError(ErrorCode.MODEL_NOT_FOUND, "Configured AI model was not found", status_code=404)
            provider = await self.session.get(AIProvider, model.provider_id)
            if provider is None:
                raise AppError(ErrorCode.PROVIDER_NOT_FOUND, "AI provider was not found", status_code=404)
            if not model.enabled or not provider.enabled:
                raise AppError(ErrorCode.PROVIDER_ERROR, "The selected AI model or provider is disabled", status_code=409)
        else:
            query = select(AIModel).where(AIModel.enabled.is_(True))
            models = list((await self.session.scalars(query)).all())
            providers = {
                p.id: p for p in (await self.session.scalars(
                    select(AIProvider).where(AIProvider.enabled.is_(True))
                )).all()
            }
            candidates = [m for m in models if m.provider_id in providers]
            flag = "is_default_translation" if purpose == "translation" else "is_default_chat"
            preferred = [m for m in candidates if getattr(m, flag)]
            if not preferred:
                preferred = [m for m in candidates if purpose in (m.capabilities or [])]
            if not preferred:
                preferred = candidates
            if not preferred:
                raise AppError(
                    ErrorCode.TRANSLATION_NOT_CONFIGURED,
                    "No AI model is configured. Add a provider and model in Settings first.",
                    status_code=409,
                )
            model = preferred[0]
            provider = providers[model.provider_id]

        assert provider is not None and model is not None
        adapter = self.adapter_factory(self._provider_config(provider), self._model_config(model))
        return ResolvedClient(provider=provider, model=model, adapter=adapter)

    async def resolve_for_test(
        self, provider_id: str, *, model_name: str | None = None
    ) -> ResolvedClient:
        provider = await self.session.get(AIProvider, provider_id)
        if provider is None:
            raise AppError(ErrorCode.PROVIDER_NOT_FOUND, "AI provider not found", status_code=404)
        model = await self.session.scalar(
            select(AIModel).where(AIModel.provider_id == provider_id).order_by(AIModel.created_at)
        )
        if model is None and not model_name:
            raise AppError(
                ErrorCode.MODEL_NOT_FOUND,
                "Add at least one model before testing this provider",
                status_code=422,
            )
        config = ModelConfig(
            id=model.id if model else "",
            name=model_name or (model.name if model else ""),
            display_name=model.display_name if model else (model_name or ""),
            context_window=model.context_window if model else 8192,
            max_output_tokens=32,
            timeout_seconds=model.timeout_seconds if model else 30,
            supports_json=model.supports_json if model else True,
            params={},
        )
        adapter = self.adapter_factory(self._provider_config(provider), config)
        return ResolvedClient(provider=provider, model=model, adapter=adapter)  # type: ignore[arg-type]
