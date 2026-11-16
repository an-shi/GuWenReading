"""Strict JSON completion helper with a single repair attempt."""

from __future__ import annotations

import json
import re
from typing import Any

from app.ai.providers.base import (
    AIProviderError, BaseChatAdapter, ChatMessage, ChatResult,
)

FENCE_RE = re.compile(r"```(?:json)?\s*(.*?)```", re.DOTALL)


def extract_json(text: str) -> Any:
    value = text.strip()
    fence = FENCE_RE.search(value)
    if fence:
        value = fence.group(1).strip()
    if not value:
        raise ValueError("empty response")
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        start = value.find("{")
        end = value.rfind("}")
        if start >= 0 and end > start:
            return json.loads(value[start : end + 1])
        start = value.find("[")
        end = value.rfind("]")
        if start >= 0 and end > start:
            return json.loads(value[start : end + 1])
        raise


async def complete_json(
    adapter: BaseChatAdapter,
    messages: list[ChatMessage],
    *,
    temperature: float = 0.2,
    max_tokens: int | None = None,
    timeout: float | None = None,
    repair: bool = True,
) -> tuple[Any, ChatResult]:
    result = await adapter.chat(
        messages, temperature=temperature, max_tokens=max_tokens, json_mode=True, timeout=timeout
    )
    try:
        return extract_json(result.text), result
    except (ValueError, json.JSONDecodeError) as first_error:
        if not repair:
            raise AIProviderError("AI returned invalid JSON") from first_error
        repair_messages = list(messages) + [
            ChatMessage(role="assistant", content=result.text[:12000]),
            ChatMessage(
                role="user",
                content=(
                    "上一条回复不是合法 JSON，或缺少所需字段。请只输出合法的 JSON 对象，"
                    "不要代码围栏、不要解释，并严格遵循最初要求的字段结构。"
                ),
            ),
        ]
        repaired = await adapter.chat(
            repair_messages,
            temperature=0,
            max_tokens=max_tokens,
            json_mode=True,
            timeout=timeout,
        )
        try:
            return extract_json(repaired.text), repaired
        except (ValueError, json.JSONDecodeError) as second_error:
            raise AIProviderError("AI returned invalid JSON after repair attempt") from second_error
