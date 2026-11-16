from __future__ import annotations

import zipfile

import httpx

from tests.conftest import import_book, SAMPLE_TEXT


async def test_import_list_and_offsets(client: httpx.AsyncClient, settings):
    book = await import_book(client)
    assert book["title"].startswith("史记")
    assert book["chapter_count"] >= 3
    assert book["sentence_count"] > 0

    listing = (await client.get("/api/v1/books")).json()["data"]
    assert listing["total"] == 1
    assert listing["items"][0]["id"] == book["id"]

    chapters = (await client.get(f"/api/v1/books/{book['id']}/chapters")).json()["data"]
    assert len(chapters) == book["chapter_count"]
    content = (await client.get(f"/api/v1/chapters/{chapters[1]['id']}/content")).json()["data"]
    extracted = (
        settings.books_dir / book["id"] / "extracted.txt"
    ).read_text(encoding="utf-8")
    assert content["paragraphs"]
    for paragraph in content["paragraphs"]:
        assert extracted[paragraph["start_offset"]:paragraph["end_offset"]] == paragraph["original_text"]
        for sentence in paragraph["sentences"]:
            assert extracted[sentence["start_offset"]:sentence["end_offset"]] == sentence["original_text"]


async def test_duplicate_import_rejected(client: httpx.AsyncClient):
    await import_book(client)
    response = await client.post(
        "/api/v1/books/import",
        files={"file": ("copy.txt", SAMPLE_TEXT.encode("utf-8"), "text/plain")},
    )
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "DUPLICATE_BOOK"


async def test_unsupported_file_rejected(client: httpx.AsyncClient):
    response = await client.post(
        "/api/v1/books/import",
        files={"file": ("book.md", b"# hello", "text/markdown")},
    )
    assert response.status_code == 415
    assert response.json()["error"]["code"] == "UNSUPPORTED_FORMAT"


async def test_book_not_found_envelope(client: httpx.AsyncClient):
    response = await client.get("/api/v1/books/does-not-exist")
    assert response.status_code == 404
    body = response.json()
    assert body["success"] is False
    assert body["error"]["code"] == "NOT_FOUND"


async def test_book_update_validation_and_metadata(client: httpx.AsyncClient):
    book = await import_book(client)
    response = await client.put(f"/api/v1/books/{book['id']}", json={
        "title": "史记（修订）", "author": "司马迁", "tags": ["正史", "西汉"],
    })
    assert response.status_code == 200
    data = response.json()["data"]
    assert data["title"] == "史记（修订）"
    assert data["tags"] == ["正史", "西汉"]
    invalid = await client.put(f"/api/v1/books/{book['id']}", json={"title": ""})
    assert invalid.status_code == 422
    assert invalid.json()["error"]["code"] == "VALIDATION_ERROR"


async def test_search_original(client: httpx.AsyncClient):
    book = await import_book(client)
    response = await client.get("/api/v1/search", params={"q": "轩辕"})
    assert response.status_code == 200
    data = response.json()["data"]
    assert data["sentences"]
    assert any(hit["book_id"] == book["id"] for hit in data["sentences"])
    assert all(hit["doc_type"] in {"original", "translation"} for hit in data["sentences"])
    assert "[[" in data["sentences"][0]["snippet"]
    assert "]]" in data["sentences"][0]["snippet"]


async def test_annotations_bookmarks_progress(client: httpx.AsyncClient):
    book = await import_book(client)
    chapter = (await client.get(f"/api/v1/books/{book['id']}/chapters")).json()["data"][1]
    sentence_id = (
        await client.get(f"/api/v1/chapters/{chapter['id']}/content")
    ).json()["data"]["paragraphs"][0]["sentences"][0]["id"]

    annotation = await client.post("/api/v1/annotations", json={
        "book_id": book["id"], "chapter_id": chapter["id"], "sentence_id": sentence_id,
        "quote": "黄帝者", "content": "此处需注意", "tags": ["人物"],
    })
    assert annotation.status_code == 201
    annotation_id = annotation.json()["data"]["id"]
    updated = await client.put(f"/api/v1/annotations/{annotation_id}", json={"content": "修订批注"})
    assert updated.json()["data"]["content"] == "修订批注"
    assert (await client.get("/api/v1/annotations", params={"book_id": book["id"]})).json()["data"]["total"] == 1
    assert (await client.delete(f"/api/v1/annotations/{annotation_id}")).status_code == 200
    assert (await client.get("/api/v1/annotations", params={"book_id": book["id"]})).json()["data"]["total"] == 0

    bookmark = await client.post("/api/v1/bookmarks", json={
        "book_id": book["id"], "chapter_id": chapter["id"], "label": "开篇", "position_ratio": 0.2,
    })
    assert bookmark.status_code == 201
    bookmark_id = bookmark.json()["data"]["id"]
    assert len((await client.get("/api/v1/bookmarks", params={"book_id": book["id"]})).json()["data"]) == 1
    assert (await client.delete(f"/api/v1/bookmarks/{bookmark_id}")).status_code == 200

    for device, ratio in (("windows-pc", 0.4), ("phone", 0.7)):
        response = await client.put("/api/v1/reading-progress", json={
            "book_id": book["id"], "chapter_id": chapter["id"],
            "device_id": device, "position_ratio": ratio,
        })
        assert response.status_code == 200
    windows = (await client.get(f"/api/v1/reading-progress/{book['id']}", params={"device_id": "windows-pc"})).json()["data"]["progress"]
    phone = (await client.get(f"/api/v1/reading-progress/{book['id']}", params={"device_id": "phone"})).json()["data"]["progress"]
    assert windows["position_ratio"] == 0.4
    assert phone["position_ratio"] == 0.7
    assert windows["id"] != phone["id"]


async def test_backup_contains_database_and_books(client: httpx.AsyncClient, settings):
    await import_book(client)
    response = await client.post("/api/v1/system/backup")
    assert response.status_code == 201, response.text
    data = response.json()["data"]
    assert data["size"] > 0
    backup_path = settings.backups_dir / data["filename"]
    assert backup_path.exists()
    with zipfile.ZipFile(backup_path) as archive:
        names = set(archive.namelist())
        assert "database/guwen.db" in names
        assert "backup.json" in names
        assert any(name.startswith("books/") for name in names)
    listing = (await client.get("/api/v1/system/backups")).json()["data"]
    assert listing and listing[0]["filename"] == data["filename"]


async def test_soft_delete_hides_book(client: httpx.AsyncClient):
    book = await import_book(client)
    response = await client.delete(f"/api/v1/books/{book['id']}")
    assert response.status_code == 200
    listing = (await client.get("/api/v1/books")).json()["data"]
    assert listing["total"] == 0
    assert (await client.get(f"/api/v1/books/{book['id']}")).status_code == 404


async def test_reparse_requires_force_when_translated(client: httpx.AsyncClient):
    book = await import_book(client)
    chapter = (await client.get(f"/api/v1/books/{book['id']}/chapters")).json()["data"][1]
    sentence_id = (
        await client.get(f"/api/v1/chapters/{chapter['id']}/content")
    ).json()["data"]["paragraphs"][0]["sentences"][0]["id"]
    created = await client.post(f"/api/v1/translations/sentence/{sentence_id}/manual", json={"text": "人工译文。"})
    assert created.status_code == 201

    blocked = await client.post(f"/api/v1/books/{book['id']}/reparse")
    assert blocked.status_code == 409
    assert blocked.json()["error"]["code"] == "REPARSE_BLOCKED"

    forced = await client.post(f"/api/v1/books/{book['id']}/reparse", params={"force": True})
    assert forced.status_code == 200, forced.text
    assert forced.json()["data"]["translated_sentence_count"] == 0
