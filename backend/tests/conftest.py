from __future__ import annotations

import asyncio
from pathlib import Path

import httpx
import pytest_asyncio

from app.core.config import Settings
from app.main import create_app
from tests.fakes import FakeAIAdapter

SAMPLE_TEXT = """史记

卷一 五帝本纪

黄帝者，少典之子，姓公孙，名曰轩辕。生而神灵，弱而能言。
轩辕之时，神农氏世衰。诸侯相侵伐，暴虐百姓，而神农氏弗能征。
于是轩辕乃习用干戈，以征不享，诸侯咸来宾从。

卷二 夏本纪

夏禹，名曰文命。禹之父曰鲧，鲧之父曰帝颛顼。
禹乃遂与益、后稷奉帝命，命诸侯百姓兴人徒以傅土，行山表木，定高山大川。
"""


@pytest_asyncio.fixture
async def settings(tmp_path: Path) -> Settings:
    return Settings(
        data_dir=tmp_path / "data",
        env="test",
        sync_enabled=True,
        secret_key="test-secret-key-for-fernet",
        task_workers=1,
    )


@pytest_asyncio.fixture
async def app(settings: Settings):
    application = create_app(settings, adapter_factory=lambda provider, model: FakeAIAdapter(provider, model))
    async with application.router.lifespan_context(application):
        yield application


@pytest_asyncio.fixture
async def client(app):
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test", timeout=30) as http_client:
        yield http_client


async def import_book(
    client: httpx.AsyncClient,
    text: str = SAMPLE_TEXT,
    filename: str = "史记.txt",
) -> dict:
    response = await client.post(
        "/api/v1/books/import",
        files={"file": (filename, text.encode("utf-8"), "text/plain")},
    )
    assert response.status_code == 201, response.text
    return response.json()["data"]


async def setup_ai(client: httpx.AsyncClient) -> tuple[str, str]:
    provider = await client.post("/api/v1/ai/providers", json={
        "name": "test-provider",
        "kind": "openai_compatible",
        "base_url": "http://127.0.0.1:1/v1",
        "api_key": "sk-test-123456789",
    })
    assert provider.status_code == 201, provider.text
    provider_id = provider.json()["data"]["id"]
    model = await client.post("/api/v1/ai/models", json={
        "provider_id": provider_id,
        "name": "test-model",
        "display_name": "Test Model",
        "context_window": 8192,
        "max_output_tokens": 2048,
        "is_default_translation": True,
        "is_default_chat": True,
    })
    assert model.status_code == 201, model.text
    return provider_id, model.json()["data"]["id"]


async def wait_task(client: httpx.AsyncClient, task_id: str, timeout: float = 20) -> dict:
    deadline = asyncio.get_event_loop().time() + timeout
    while asyncio.get_event_loop().time() < deadline:
        response = await client.get(f"/api/v1/tasks/{task_id}")
        task = response.json()["data"]
        if task["status"] in {"completed", "partial", "failed", "cancelled"}:
            return task
        await asyncio.sleep(0.1)
    raise AssertionError(f"Task {task_id} did not finish within {timeout}s")


async def first_chapter_with_text(client: httpx.AsyncClient, book_id: str) -> tuple[dict, dict]:
    chapters = (await client.get(f"/api/v1/books/{book_id}/chapters")).json()["data"]
    for chapter in chapters:
        if chapter["sentence_count"] >= 2:
            content = (await client.get(f"/api/v1/chapters/{chapter['id']}/content")).json()["data"]
            if any(p["sentences"] for p in content["paragraphs"]):
                return chapter, content
    raise AssertionError("No text chapters found")
