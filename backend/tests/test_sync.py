from __future__ import annotations

import httpx

from tests.conftest import first_chapter_with_text, import_book


async def _push(client: httpx.AsyncClient, device_id: str, operations: list[dict]) -> dict:
    response = await client.post("/api/v1/sync/push", json={
        "device_id": device_id, "operations": operations,
    })
    assert response.status_code == 200, response.text
    return response.json()["data"]


async def test_manual_translation_prevents_ai_overwrite(client: httpx.AsyncClient):
    book = await import_book(client)
    chapter, content = await first_chapter_with_text(client, book["id"])
    sentence = content["paragraphs"][0]["sentences"][0]

    manual = await _push(client, "desktop", [{
        "entity_type": "translation", "entity_id": "translation-manual-1",
        "operation": "upsert", "base_version": 0, "version": 1,
        "data": {
            "sentence_id": sentence["id"], "text": "桌面人工译文。",
            "origin": "manual", "status": "completed",
        },
    }])
    assert manual["results"][0]["status"] == "applied"

    ai = await _push(client, "phone", [{
        "entity_type": "translation", "entity_id": "translation-ai-1",
        "operation": "upsert", "base_version": 0, "version": 1,
        "data": {
            "sentence_id": sentence["id"], "text": "手机 AI 译文。",
            "origin": "ai", "status": "completed",
        },
    }])
    assert ai["results"][0]["status"] == "conflict"

    status = (await client.get("/api/v1/sync/status", params={"device_id": "phone"})).json()["data"]
    assert status["pending_conflicts"] == 1
    conflicts = (await client.get("/api/v1/sync/conflicts")).json()["data"]
    assert conflicts and conflicts[0]["entity_type"] == "translation"

    resolved = await client.post(
        f"/api/v1/sync/conflicts/{conflicts[0]['seq']}/resolve",
        params={"action": "accept_server"},
    )
    assert resolved.status_code == 200
    assert resolved.json()["data"]["status"] == "resolved_server"
    detail = (await client.get(f"/api/v1/translations/sentence/{sentence['id']}")).json()["data"]
    assert detail["translation"]["text"] == "桌面人工译文。"


async def test_pull_downloads_other_device_changes(client: httpx.AsyncClient):
    book = await import_book(client)
    chapter, content = await first_chapter_with_text(client, book["id"])
    sentence = content["paragraphs"][0]["sentences"][0]

    await _push(client, "desktop", [{
        "entity_type": "annotation", "entity_id": "anno-1", "operation": "upsert",
        "base_version": 0, "version": 1,
        "data": {
            "book_id": book["id"], "chapter_id": chapter["id"],
            "sentence_id": sentence["id"], "quote": sentence["original_text"],
            "content": "桌面批注", "tags": ["人物"],
        },
    }])
    await _push(client, "desktop", [{
        "entity_type": "reading_progress", "entity_id": "progress-desktop",
        "operation": "upsert", "base_version": 0, "version": 1,
        "data": {
            "book_id": book["id"], "device_id": "desktop", "chapter_id": chapter["id"],
            "position_ratio": 0.35,
        },
    }])
    await _push(client, "phone", [{
        "entity_type": "reading_progress", "entity_id": "progress-phone",
        "operation": "upsert", "base_version": 0, "version": 1,
        "data": {
            "book_id": book["id"], "device_id": "phone", "chapter_id": chapter["id"],
            "position_ratio": 0.72,
        },
    }])

    pull = (await client.get("/api/v1/sync/pull", params={
        "device_id": "phone", "after": 0,
    })).json()["data"]
    assert pull["operations"]
    assert pull["next_cursor"] > 0
    annotations = [op for op in pull["operations"] if op["entity_type"] == "annotation"]
    assert annotations and annotations[0]["data"]["content"] == "桌面批注"

    desktop = (await client.get(f"/api/v1/reading-progress/{book['id']}", params={"device_id": "desktop"})).json()["data"]["progress"]
    phone = (await client.get(f"/api/v1/reading-progress/{book['id']}", params={"device_id": "phone"})).json()["data"]["progress"]
    assert desktop["position_ratio"] == 0.35
    assert phone["position_ratio"] == 0.72
    assert desktop["id"] != phone["id"]


async def test_sync_conflict_can_accept_client(client: httpx.AsyncClient):
    book = await import_book(client)
    chapter, _ = await first_chapter_with_text(client, book["id"])
    await _push(client, "desktop", [{
        "entity_type": "annotation", "entity_id": "conflict-anno", "operation": "upsert",
        "base_version": 0, "version": 1,
        "data": {"book_id": book["id"], "chapter_id": chapter["id"], "content": "服务端版本", "color": "amber"},
    }])
    stale = await _push(client, "phone", [{
        "entity_type": "annotation", "entity_id": "conflict-anno", "operation": "upsert",
        "base_version": 0, "version": 1, "updated_at": "2000-01-01T00:00:00Z",
        "data": {"book_id": book["id"], "chapter_id": chapter["id"], "content": "客户端旧版本", "color": "blue"},
    }])
    assert stale["results"][0]["status"] == "conflict"
    conflicts = (await client.get("/api/v1/sync/conflicts")).json()["data"]
    seq = conflicts[0]["seq"]
    resolved = await client.post(
        f"/api/v1/sync/conflicts/{seq}/resolve", params={"action": "accept_client"}
    )
    assert resolved.json()["data"]["status"] == "applied"
    annotations = (await client.get("/api/v1/annotations", params={"book_id": book["id"]})).json()["data"]["items"]
    assert annotations[0]["content"] == "客户端旧版本"


async def test_sync_disabled_returns_clear_error(settings, monkeypatch):
    settings.sync_enabled = False
    settings.mode = "embedded"
    # The service checks current settings at call time; use a direct call for the guard.
    from app.core.errors import AppError
    from app.modules.sync.service import SyncService
    try:
        SyncService(settings).ensure_enabled()
    except AppError as exc:
        assert exc.code == "SYNC_DISABLED"
    else:
        raise AssertionError("sync should be disabled")
