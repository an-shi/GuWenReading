"""Provider-neutral chat interfaces."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


class AIProviderError(Exception):
    def __init__(self, message: str, *, retryable: bool = False, status_code: int | None = None) -> None:
        super().__init__(message)
        self.message = message
        self.retryable = retryable
        self.status_code = status_code


@dataclass(frozen=True)
class ChatMessage:
    role: str
    content: str


@dataclass
class ChatResult:
    text: str
    model: str
    usage: dict[str, Any] = field(default_factory=dict)
    raw: dict[str, Any] = field(default_factory=dict)


@dataclass
class ProviderConfig:
    id: str
    name: str
    kind: str
    base_url: str
    api_key: str
    headers: dict[str, str] = field(default_factory=dict)


@dataclass
class ModelConfig:
    id: str
    name: str
    display_name: str
    context_window: int = 8192
    max_output_tokens: int = 2048
    timeout_seconds: int = 120
    supports_json: bool = True
    supports_streaming: bool = False
    params: dict[str, Any] = field(default_factory=dict)


class BaseChatAdapter:
    provider: ProviderConfig
    model: ModelConfig

    async def chat(
        self,
        messages: list[ChatMessage],
        *,
        temperature: float = 0.2,
        max_tokens: int | None = None,
        json_mode: bool = False,
        timeout: float | None = None,
    ) -> ChatResult:  # pragma: no cover - interface
        raise NotImplementedError

    async def test(self, *, timeout: float = 30.0) -> dict[str, Any]:  # pragma: no cover
        raise NotImplementedError
