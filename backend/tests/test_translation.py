from __future__ import annotations

import httpx
from sqlalchemy import delete, update

from app.core.config import Settings
from app.database.models import Sentence, Translation
from app.main import create_app
from tests.conftest import (
    first_chapter_with_text, import_book, setup_ai, wait_task,
)
from tests.fakes import BrokenAIAdapter


async def test_chapter_translation_manual_edit_and_review(client: httpx.AsyncClient):
    await setup_ai(client)
    book = await import_book(client)
    chapter, content = await first_chapter_with_text(client, book["id"])
    sentences = [s for p in content["paragraphs"] for s in p["sentences"]]
    assert len(sentences) >= 2

    response = await client.post(f"/api/v1/translations/chapter/{chapter['id']}")
    assert response.status_code == 202, response.text
    task = await wait_task(client, response.json()["data"]["id"])
    assert task["status"] == "completed", task
    assert task["completed"] == len(sentences)
    assert task["result"]["prompt_version"] == 1

    refreshed = (await client.get(f"/api/v1/chapters/{chapter['id']}/content")).json()["data"]
    translated = [s for p in refreshed["paragraphs"] for s in p["sentences"]]
    assert all(s["translation_state"] == "completed" for s in translated)
    assert all(s["translation"]["origin"] == "ai" for s in translated)
    first = translated[0]

    search = (await client.get("/api/v1/search", params={"q": "现代译文", "scope": "translation"})).json()["data"]
    assert search["sentences"]

    edit = await client.put(f"/api/v1/translations/{first['translation']['id']}", json={
        "text": "这是人工修订后的译文。", "note": "润色",
    })
    assert edit.status_code == 200
    assert edit.json()["data"]["origin"] == "manual"
    assert edit.json()["data"]["text"] == "这是人工修订后的译文。"

    retranslate = await client.post(f"/api/v1/translations/retranslate/{first['translation']['id']}")
    assert retranslate.status_code == 202
    retranslate_task = await wait_task(client, retranslate.json()["data"]["id"])
    assert retranslate_task["status"] == "completed"

    detail = (await client.get(f"/api/v1/translations/sentence/{first['id']}")).json()["data"]
    assert detail["translation"]["origin"] == "manual"
    assert detail["translation"]["text"] == "这是人工修订后的译文。"
    assert len(detail["reviews"]) == 1
    assert detail["reviews"][0]["status"] == "pending"

    review_id = detail["reviews"][0]["id"]
    accept = await client.post(f"/api/v1/translations/reviews/{review_id}/resolve", json={"action": "accept"})
    assert accept.status_code == 200, accept.text
    assert accept.json()["data"]["status"] == "accepted"
    after = (await client.get(f"/api/v1/translations/sentence/{first['id']}")).json()["data"]
    assert after["translation"]["text"] == detail["reviews"][0]["candidate_text"]
    assert after["translation"]["origin"] == "ai"
    versions = (await client.get(f"/api/v1/translations/{first['translation']['id']}/versions")).json()["data"]
    assert len(versions) >= 2


async def test_translation_cache_prevents_repeated_ai_calls(
    client: httpx.AsyncClient, app
):
    await setup_ai(client)
    book = await import_book(client)
    chapter, content = await first_chapter_with_text(client, book["id"])
    total_sentences = sum(len(p["sentences"]) for p in content["paragraphs"])

    first = await client.post(f"/api/v1/translations/chapter/{chapter['id']}")
    task = await wait_task(client, first.json()["data"]["id"])
    assert task["status"] == "completed"
    assert task["result"]["cached"] == 0

    # Simulate a fresh client that lost local translation rows but kept cache.
    async with app.state.session_factory() as session:
        await session.execute(delete(Translation).where(Translation.chapter_id == chapter["id"]))
        await session.execute(
            update(Sentence).where(Sentence.chapter_id == chapter["id"]).values(
                translation_state="pending", translated_at=None
            )
        )
        await session.commit()

    second = await client.post(f"/api/v1/translations/chapter/{chapter['id']}")
    assert second.status_code == 202, second.text
    task2 = await wait_task(client, second.json()["data"]["id"])
    assert task2["status"] == "completed"
    assert task2["result"]["cached"] == total_sentences
    assert task2["result"]["completed"] == total_sentences


async def test_translation_failure_is_recorded(settings: Settings):
    broken_settings = Settings(
        data_dir=settings.data_dir.parent / "broken",
        env="test",
        secret_key="broken-secret",
        task_workers=1,
    )
    application = create_app(
        broken_settings, adapter_factory=lambda provider, model: BrokenAIAdapter(provider, model)
    )
    async with application.router.lifespan_context(application):
        transport = httpx.ASGITransport(app=application)
        async with httpx.AsyncClient(transport=transport, base_url="http://test", timeout=30) as client:
            await setup_ai(client)
            book = await import_book(client)
            chapter, _ = await first_chapter_with_text(client, book["id"])
            response = await client.post(f"/api/v1/translations/chapter/{chapter['id']}")
            task = await wait_task(client, response.json()["data"]["id"])
            assert task["status"] == "failed"
            assert task["failed_count"] > 0
            assert task["result"]["abort_reason"]
            content = (await client.get(f"/api/v1/chapters/{chapter['id']}/content")).json()["data"]
            sentences = [s for p in content["paragraphs"] for s in p["sentences"]]
            assert any(s["translation_state"] == "failed" for s in sentences)
            assert all(s["translation"] is None for s in sentences)


async def test_manual_translation_can_be_created_without_ai(client: httpx.AsyncClient):
    book = await import_book(client)
    chapter, content = await first_chapter_with_text(client, book["id"])
    sentence = content["paragraphs"][0]["sentences"][0]
    created = await client.post(
        f"/api/v1/translations/sentence/{sentence['id']}/manual",
        json={"text": "这是直接录入的人工译文。"},
    )
    assert created.status_code == 201
    assert created.json()["data"]["origin"] == "manual"
    duplicate = await client.post(
        f"/api/v1/translations/sentence/{sentence['id']}/manual",
        json={"text": "重复"},
    )
    assert duplicate.status_code == 409
