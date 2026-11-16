"""Ollama native chat adapter."""

from __future__ import annotations

import time
from typing import Any

import httpx

from app.ai.providers.base import (
    AIProviderError, BaseChatAdapter, ChatMessage, ChatResult, ModelConfig, ProviderConfig,
)


class OllamaAdapter(BaseChatAdapter):
    def __init__(self, provider: ProviderConfig, model: ModelConfig) -> None:
        self.provider = provider
        self.model = model

    @property
    def endpoint(self) -> str:
        base = self.provider.base_url.rstrip("/")
        return base if base.endswith("/api/chat") else f"{base}/api/chat"

    async def chat(
        self,
        messages: list[ChatMessage],
        *,
        temperature: float = 0.2,
        max_tokens: int | None = None,
        json_mode: bool = False,
        timeout: float | None = None,
    ) -> ChatResult:
        payload: dict[str, Any] = {
            "model": self.model.name,
            "messages": [{"role": m.role, "content": m.content} for m in messages],
            "stream": False,
            "options": {
                "temperature": temperature,
                "num_predict": max_tokens or self.model.max_output_tokens,
                **(self.model.params or {}),
            },
        }
        if json_mode:
            payload["format"] = "json"
        headers = {"Content-Type": "application/json", **self.provider.headers}
        if self.provider.api_key:
            headers["Authorization"] = f"Bearer {self.provider.api_key}"
        try:
            async with httpx.AsyncClient(
                timeout=timeout or self.model.timeout_seconds, follow_redirects=True
            ) as client:
                response = await client.post(self.endpoint, json=payload, headers=headers)
        except httpx.TimeoutException as exc:
            raise AIProviderError("Ollama request timed out", retryable=True) from exc
        except httpx.NetworkError as exc:
            raise AIProviderError(f"Ollama is unreachable: {exc}", retryable=True) from exc

        if response.status_code >= 400:
            raise AIProviderError(
                f"Ollama request failed ({response.status_code}): {response.text[:300]}",
                retryable=response.status_code >= 500,
            )
        try:
            data = response.json()
            text = data["message"]["content"]
        except (ValueError, KeyError, TypeError) as exc:
            raise AIProviderError("Ollama returned an invalid response") from exc
        if not isinstance(text, str) or not text.strip():
            raise AIProviderError("Ollama returned empty content", retryable=True)
        return ChatResult(
            text=text,
            model=str(data.get("model") or self.model.name),
            usage={
                "prompt_tokens": data.get("prompt_eval_count"),
                "completion_tokens": data.get("eval_count"),
            },
            raw=data,
        )

    async def test(self, *, timeout: float = 30.0) -> dict[str, Any]:
        started = time.perf_counter()
        result = await self.chat(
            [ChatMessage(role="user", content="Reply with OK.")],
            temperature=0.0, max_tokens=16, timeout=timeout,
        )
        return {
            "ok": True,
            "latency_ms": round((time.perf_counter() - started) * 1000),
            "model": result.model,
            "reply": result.text.strip()[:200],
        }
