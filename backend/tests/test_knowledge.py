from __future__ import annotations

import httpx
import pytest

from app.modules.knowledge.chronology import parse_time
from tests.conftest import first_chapter_with_text, import_book, setup_ai, wait_task


@pytest.mark.parametrize(
    ("raw", "dynasty", "expected_year", "expected_precision"),
    [
        ("贞观三年", "唐", 629, "year"),
        ("开元二十九年", "唐", 741, "year"),
        ("建安十三年", "汉", 208, "year"),
        ("乾隆六十年", "清", 1795, "year"),
        ("公元618年", None, 618, "year"),
        ("贞观元年至贞观十年", "唐", 627, "range"),
    ],
)
def test_chronology_conversion(raw, dynasty, expected_year, expected_precision):
    parsed = parse_time(raw, dynasty=dynasty)
    assert parsed.year_start == expected_year
    assert parsed.precision == expected_precision


def test_chronology_preserves_ambiguous_and_unknown():
    ambiguous = parse_time("上元三年")
    assert ambiguous.year_start is None
    assert "多个起始年份" in (ambiguous.note or "")
    unknown = parse_time("是岁")
    assert unknown.year_start is None
    assert unknown.precision == "unknown"
    unknown_era = parse_time("天书三年")
    assert unknown_era.year_start is None


async def test_knowledge_extraction_graph_timeline_and_assistant(client: httpx.AsyncClient):
    await setup_ai(client)
    book = await import_book(client)
    chapter, content = await first_chapter_with_text(client, book["id"])

    response = await client.post("/api/v1/knowledge/extract", json={"chapter_id": chapter["id"]})
    assert response.status_code == 202, response.text
    task = await wait_task(client, response.json()["data"]["id"])
    assert task["status"] == "completed", task
    assert task["result"]["entities_created"] >= 2
    assert task["result"]["mentions_created"] >= 2
    assert task["result"]["relations_created"] == 1
    assert task["result"]["events_created"] == 1

    entities = (await client.get("/api/v1/entities")).json()["data"]
    assert entities["total"] >= 2
    names = {entity["canonical_name"] for entity in entities["items"]}
    assert {"黄帝", "神农氏"} <= names
    assert all(entity["status"] == "pending" for entity in entities["items"])
    huangdi = next(entity for entity in entities["items"] if entity["canonical_name"] == "黄帝")
    assert "轩辕" in huangdi["aliases"]

    detail = (await client.get(f"/api/v1/entities/{huangdi['id']}")).json()["data"]
    assert detail["mentions"]
    assert detail["mentions"][0]["quote"]
    assert detail["mentions"][0]["status"] == "pending"

    graph = (await client.get("/api/v1/graph")).json()["data"]
    assert len(graph["nodes"]) == 2
    assert len(graph["edges"]) == 1
    assert graph["edges"][0]["relation_type"] == "敌对"
    assert graph["edges"][0]["status"] == "inferred"
    assert graph["edges"][0]["sources"]

    relation_id = graph["edges"][0]["id"]
    confirmed = await client.put(f"/api/v1/relations/{relation_id}/review", params={"status": "confirmed"})
    assert confirmed.status_code == 200

    timeline = (await client.get("/api/v1/timeline")).json()["data"]
    assert len(timeline["events"]) == 1
    event = timeline["events"][0]
    assert event["name"] == "轩辕征不享"
    assert event["time_start_year"] == 629
    assert event["time_raw"] == "贞观三年"
    assert event["participants"] == ["黄帝"]
    assert event["source_count"] == 1

    event_detail = (await client.get(f"/api/v1/events/{event['id']}")).json()["data"]
    assert event_detail["sources"]
    assert event_detail["sources"][0]["quote"]
    reviewed = await client.put(f"/api/v1/events/{event['id']}/review", params={"status": "confirmed"})
    assert reviewed.json()["data"]["status"] == "confirmed"

    assistant = await client.post("/api/v1/assistant/chat", json={
        "question": "黄帝是谁？", "book_id": book["id"], "chapter_id": chapter["id"],
    })
    assert assistant.status_code == 200, assistant.text
    answer = assistant.json()["data"]
    assert answer["answer"]
    assert answer["citations"]
    assert answer["citations"][0]["verified"] is True
    assert answer["claims"][0]["kind"] == "explicit"
    assert answer["local_sources"]
    session = (await client.get(f"/api/v1/assistant/sessions/{answer['session_id']}")).json()["data"]
    assert len(session["messages"]) == 2

    search = (await client.get("/api/v1/search", params={"q": "神农氏"})).json()["data"]
    assert any(entity["canonical_name"] == "神农氏" for entity in search["entities"])


async def test_entity_merge_reassigns_mentions(client: httpx.AsyncClient):
    await setup_ai(client)
    book = await import_book(client)
    chapter, _ = await first_chapter_with_text(client, book["id"])
    await wait_task(client, (await client.post(
        "/api/v1/knowledge/extract", json={"chapter_id": chapter["id"]}
    )).json()["data"]["id"])
    entities = (await client.get("/api/v1/entities")).json()["data"]["items"]
    target = next(entity for entity in entities if entity["canonical_name"] == "黄帝")
    created = await client.post("/api/v1/entities", json={
        "canonical_name": "轩辕氏（重复条目）", "kind": "person", "dynasty": "上古",
    })
    source_id = created.json()["data"]["id"]
    merged = await client.post(f"/api/v1/entities/{target['id']}/merge", json={
        "source_entity_ids": [source_id],
    })
    assert merged.status_code == 200, merged.text
    assert "轩辕氏（重复条目）" in merged.json()["data"]["aliases"]
    source = await client.get(f"/api/v1/entities/{source_id}")
    assert source.status_code == 404
