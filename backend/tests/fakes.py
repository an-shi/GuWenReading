"""Deterministic fake AI adapters for offline tests."""

from __future__ import annotations

import json
import re
from typing import Any

from app.ai.providers.base import BaseChatAdapter, ChatResult, ModelConfig, ProviderConfig

UUID_RE = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")


def _section(content: str, start: str, end: str | None = None) -> str:
    index = content.find(start)
    if index < 0:
        return ""
    value = content[index + len(start):]
    if end:
        stop = value.find(end)
        if stop >= 0:
            value = value[:stop]
    return value


class FakeAIAdapter(BaseChatAdapter):
    def __init__(self, provider: ProviderConfig, model: ModelConfig) -> None:
        self.provider = provider
        self.model = model

    async def test(self, *, timeout: float = 30.0) -> dict[str, Any]:
        return {"ok": True, "latency_ms": 1, "model": self.model.name, "reply": "OK"}

    async def chat(
        self, messages, *, temperature=0.2, max_tokens=None, json_mode=False, timeout=None
    ) -> ChatResult:
        content = messages[-1].content
        if "古籍阅读助手" in content:
            payload = self._assistant(content)
        elif "抽取历史实体" in content:
            payload = self._entities(content)
        elif "关系抽取器" in content:
            payload = self._relations(content)
        elif "事件抽取器" in content:
            payload = self._events(content)
        elif "待译句子" in content:
            payload = self._translations(content)
        elif "质量检查" in content or "审校" in content:
            payload = {"verdict": "pass", "issues": [], "suggested_translation": "", "confidence": 0.8}
        else:
            payload = {"ok": True}
        return ChatResult(
            text=json.dumps(payload, ensure_ascii=False), model=self.model.name,
            usage={"prompt_tokens": 10, "completion_tokens": 10},
        )

    def _translations(self, content: str) -> dict[str, Any]:
        raw = _section(content, "【待译句子（JSON 数组）】", "只输出")
        if not raw:
            raw = _section(content, "【待译句子】", "只输出")
        try:
            items = json.loads(raw.strip())
        except (ValueError, json.JSONDecodeError):
            items = [{"id": value} for value in UUID_RE.findall(content)]
        return {
            "translations": [
                {"id": item["id"], "text": f"现代译文：{item.get('text', '')[:20]}", "uncertain": False, "note": ""}
                for item in items if isinstance(item, dict) and item.get("id")
            ]
        }

    def _paragraphs(self, content: str) -> list[dict[str, Any]]:
        raw = _section(content, "【按段落组织的句子】", "只输出")
        if not raw:
            raw = _section(content, "【原文句子】", "只输出")
        if not raw:
            raw = _section(content, "【原文】", "【")
        try:
            return json.loads(raw.strip())
        except (ValueError, json.JSONDecodeError):
            return []

    @staticmethod
    def _ids(paragraphs: list[dict[str, Any]]) -> list[str]:
        return [
            sentence["id"]
            for paragraph in paragraphs
            for sentence in paragraph.get("sentences", [])
            if sentence.get("id")
        ]

    def _entities(self, content: str) -> dict[str, Any]:
        paragraphs = self._paragraphs(content)
        ids = self._ids(paragraphs)
        mentions = []
        if ids:
            mentions.append({
                "entity_name": "黄帝", "sentence_id": ids[0],
                "surface_text": "黄帝", "confidence": 0.95,
            })
            shennong_id = next(
                (
                    sentence["id"]
                    for paragraph in paragraphs
                    for sentence in paragraph.get("sentences", [])
                    if "神农氏" in sentence.get("text", "")
                ),
                ids[1] if len(ids) > 1 else None,
            )
            if shennong_id:
                mentions.append({
                    "entity_name": "神农氏", "sentence_id": shennong_id,
                    "surface_text": "神农氏", "confidence": 0.85,
                })
        return {
            "entities": [
                {
                    "name": "黄帝", "kind": "person", "dynasty": "上古",
                    "aliases": ["轩辕"], "identity": "部落首领",
                    "summary": "黄帝，姓公孙，名轩辕。", "confidence": 0.9,
                },
                {
                    "name": "神农氏", "kind": "person", "dynasty": "上古",
                    "aliases": [], "identity": "部落首领",
                    "summary": "神农氏世衰。", "confidence": 0.8,
                },
            ],
            "mentions": mentions,
        }

    def _relations(self, content: str) -> dict[str, Any]:
        paragraphs = self._paragraphs(content)
        ids = self._ids(paragraphs)
        return {
            "relations": [
                {
                    "source": "黄帝", "target": "神农氏", "type": "敌对",
                    "label": "征伐", "description": "轩辕以征不享。",
                    "evidence_ids": ids[:1], "explicit": False, "confidence": 0.6,
                }
            ] if ids else []
        }

    def _events(self, content: str) -> dict[str, Any]:
        paragraphs = self._paragraphs(content)
        ids = self._ids(paragraphs)
        return {
            "events": [
                {
                    "name": "轩辕征不享", "type": "战争",
                    "description": "轩辕习用干戈，以征不享。",
                    "time_raw": "贞观三年", "era_name": "贞观", "reign_year": "三年",
                    "ganzhi": "", "dynasty": "唐", "precision": "year",
                    "participants": ["黄帝"], "evidence_ids": ids[:1], "confidence": 0.7,
                }
            ] if ids else []
        }

    def _assistant(self, content: str) -> dict[str, Any]:
        matches = re.findall(r"\[句 ([0-9a-f\-]{36})\] 原文：([^\n]+)", content)
        sentence_id, quote = (matches[0][0], matches[0][1]) if matches else (None, "")
        return {
            "answer": "黄帝，姓公孙，名轩辕。",
            "citations": [
                {
                    "book": "史记", "chapter": "五帝本纪", "sentence_id": sentence_id,
                    "quote": quote, "note": "原文明确记载",
                }
            ],
            "claims": [{"text": "黄帝名轩辕", "kind": "explicit"}],
        }


class BrokenAIAdapter(BaseChatAdapter):
    def __init__(self, provider: ProviderConfig, model: ModelConfig) -> None:
        self.provider = provider
        self.model = model

    async def test(self, *, timeout: float = 30.0) -> dict[str, Any]:
        return {"ok": True, "latency_ms": 1, "model": self.model.name, "reply": "OK"}

    async def chat(self, messages, *, temperature=0.2, max_tokens=None, json_mode=False, timeout=None):
        return ChatResult(text="this is not json", model=self.model.name)
