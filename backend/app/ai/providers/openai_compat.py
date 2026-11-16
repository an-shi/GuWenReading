"""OpenAI-compatible chat completions adapter.

Works with OpenAI, DeepSeek, Moonshot, Zhipu-compatible gateways, vLLM, LM Studio
and any other server implementing POST /chat/completions.
"""

from __future__ import annotations

import time
from typing import Any

import httpx
from tenacity import (
    AsyncRetrying, retry_if_exception, stop_after_attempt, wait_exponential,
)

from app.ai.providers.base import (
    AIProviderError, BaseChatAdapter, ChatMessage, ChatResult, ModelConfig, ProviderConfig,
)


def _is_retryable(exc: BaseException) -> bool:
    if isinstance(exc, AIProviderError):
        return exc.retryable
    return isinstance(exc, (httpx.TimeoutException, httpx.NetworkError))


class OpenAICompatibleAdapter(BaseChatAdapter):
    def __init__(self, provider: ProviderConfig, model: ModelConfig) -> None:
        self.provider = provider
        self.model = model

    @property
    def endpoint(self) -> str:
        base = self.provider.base_url.rstrip("/")
        if base.endswith("/chat/completions"):
            return base
        return f"{base}/chat/completions"

    def _headers(self) -> dict[str, str]:
        headers = {"Content-Type": "application/json", **self.provider.headers}
        if self.provider.api_key:
            headers["Authorization"] = f"Bearer {self.provider.api_key}"
        return headers

    async def chat(
        self,
        messages: list[ChatMessage],
        *,
        temperature: float = 0.2,
        max_tokens: int | None = None,
        json_mode: bool = False,
        timeout: float | None = None,
    ) -> ChatResult:
        use_json = bool(json_mode and self.model.supports_json)
        payload: dict[str, Any] = {
            "model": self.model.name,
            "messages": [{"role": m.role, "content": m.content} for m in messages],
            "temperature": temperature,
            "max_tokens": min(max_tokens or self.model.max_output_tokens, self.model.max_output_tokens),
            "stream": False,
        }
        if use_json:
            payload["response_format"] = {"type": "json_object"}
        payload.update(self.model.params or {})

        result = await self._request(payload, timeout=timeout)
        if result is None and use_json:
            # Some compatible servers reject response_format; retry as plain text.
            payload.pop("response_format", None)
            result = await self._request(payload, timeout=timeout)
        if result is None:  # pragma: no cover - defensive
            raise AIProviderError("Provider returned no response", retryable=True)
        return result

    async def _request(
        self, payload: dict[str, Any], *, timeout: float | None = None
    ) -> ChatResult | None:
        async def attempt() -> ChatResult:
            async with httpx.AsyncClient(
                timeout=timeout or self.model.timeout_seconds,
                follow_redirects=True,
            ) as client:
                try:
                    response = await client.post(
                        self.endpoint, json=payload, headers=self._headers()
                    )
                except httpx.TimeoutException as exc:
                    raise AIProviderError("AI provider request timed out", retryable=True) from exc
                except httpx.NetworkError as exc:
                    raise AIProviderError(f"AI provider is unreachable: {exc}", retryable=True) from exc

                if response.status_code == 429:
                    raise AIProviderError("AI provider rate limited the request", retryable=True, status_code=429)
                if response.status_code >= 500:
                    raise AIProviderError(
                        f"AI provider server error ({response.status_code})",
                        retryable=True, status_code=response.status_code,
                    )
                if response.status_code == 400 and "response_format" in payload:
                    return None
                if response.status_code in {401, 403}:
                    raise AIProviderError(
                        "AI provider rejected the API key or permissions",
                        status_code=response.status_code,
                    )
                if response.status_code >= 400:
                    detail = response.text[:500]
                    raise AIProviderError(
                        f"AI provider request failed ({response.status_code}): {detail}",
                        status_code=response.status_code,
                    )
                try:
                    data = response.json()
                except ValueError as exc:
                    raise AIProviderError("AI provider returned invalid JSON", retryable=True) from exc

                try:
                    choice = data["choices"][0]["message"]["content"]
                except (KeyError, IndexError, TypeError) as exc:
                    raise AIProviderError("AI provider response has no message content") from exc
                if isinstance(choice, list):
                    choice = "".join(
                        part.get("text", "") for part in choice if isinstance(part, dict)
                    )
                if not isinstance(choice, str) or not choice.strip():
                    raise AIProviderError("AI provider returned empty content", retryable=True)
                return ChatResult(
                    text=choice,
                    model=str(data.get("model") or payload["model"]),
                    usage=data.get("usage") or {},
                    raw=data,
                )

        async for attempt_result in AsyncRetrying(
            retry=retry_if_exception(_is_retryable),
            wait=wait_exponential(multiplier=1, min=1, max=10),
            stop=stop_after_attempt(3),
            reraise=True,
        ):
            with attempt_result:
                return await attempt()
        return None

    async def test(self, *, timeout: float = 30.0) -> dict[str, Any]:
        started = time.perf_counter()
        result = await self.chat(
            [ChatMessage(role="user", content="Reply with the single word OK.")],
            temperature=0.0,
            max_tokens=16,
            timeout=timeout,
        )
        return {
            "ok": True,
            "latency_ms": round((time.perf_counter() - started) * 1000),
            "model": result.model,
            "reply": result.text.strip()[:200],
        }
