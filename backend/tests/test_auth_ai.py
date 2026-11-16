from __future__ import annotations

from pathlib import Path

import httpx

from app.core.config import Settings
from app.main import create_app
from tests.conftest import setup_ai


async def test_server_mode_requires_authentication(tmp_path: Path):
    settings = Settings(
        data_dir=tmp_path / "server", mode="server", env="test",
        secret_key="server-test-secret", auth_secret="server-auth-secret",
    )
    application = create_app(settings)
    async with application.router.lifespan_context(application):
        transport = httpx.ASGITransport(app=application)
        async with httpx.AsyncClient(transport=transport, base_url="http://test", timeout=30) as client:
            unauthorized = await client.get("/api/v1/books")
            assert unauthorized.status_code == 401
            assert unauthorized.json()["error"]["code"] == "AUTH_REQUIRED"

            registered = await client.post("/api/v1/auth/register", json={
                "username": "owner", "password": "very-secret-password", "display_name": "Owner",
            })
            assert registered.status_code == 200, registered.text
            token = registered.json()["data"]["token"]
            headers = {"Authorization": f"Bearer {token}"}

            books = await client.get("/api/v1/books", headers=headers)
            assert books.status_code == 200
            me = await client.get("/api/v1/auth/me", headers=headers)
            assert me.json()["data"]["authenticated"] is True

            second = await client.post("/api/v1/auth/register", json={
                "username": "intruder", "password": "very-secret-password",
            })
            assert second.status_code == 403

            login = await client.post("/api/v1/auth/login", json={
                "username": "owner", "password": "very-secret-password",
            })
            assert login.status_code == 200
            bad_login = await client.post("/api/v1/auth/login", json={
                "username": "owner", "password": "wrong-password",
            })
            assert bad_login.status_code == 401

            device = await client.post("/api/v1/devices/register", headers=headers, json={
                "name": "My Phone", "platform": "android", "fingerprint": "phone-fp-1",
            })
            assert device.status_code == 200
            device_id = device.json()["data"]["id"]
            listed = await client.get("/api/v1/devices", headers=headers)
            assert listed.json()["data"][0]["name"] == "My Phone"
            deleted = await client.delete(f"/api/v1/devices/{device_id}", headers=headers)
            assert deleted.json()["data"]["removed"] is True

            # Invalid token is rejected even for public-looking routes.
            forged = await client.get("/api/v1/books", headers={"Authorization": "Bearer invalid"})
            assert forged.status_code == 401


async def test_api_keys_never_returned_and_are_encrypted(client: httpx.AsyncClient, app):
    provider_id, _ = await setup_ai(client)
    listing = await client.get("/api/v1/ai/providers")
    text = listing.text
    assert "sk-test-123456789" not in text
    assert "api_key_encrypted" not in text
    provider = listing.json()["data"][0]
    assert provider["has_api_key"] is True
    assert provider["api_key_hint"] == "****6789"

    async with app.state.session_factory() as session:
        from app.database.models import AIProvider

        stored = await session.get(AIProvider, provider_id)
        assert stored.api_key_encrypted
        assert "sk-test-123456789" not in stored.api_key_encrypted
        assert stored.api_key_encrypted.startswith(("dpapi:", "fernet:", "env:"))


async def test_provider_test_and_invalid_url(client: httpx.AsyncClient):
    provider_id, _ = await setup_ai(client)
    result = await client.post(f"/api/v1/ai/providers/{provider_id}/test", json={})
    assert result.status_code == 200, result.text
    assert result.json()["data"]["ok"] is True
    assert result.json()["data"]["reply"] == "OK"

    invalid = await client.post("/api/v1/ai/providers", json={
        "name": "bad", "base_url": "not-a-url",
    })
    assert invalid.status_code == 422


async def test_prompt_version_management(client: httpx.AsyncClient):
    prompts = (await client.get("/api/v1/ai/prompts")).json()["data"]
    keys = {prompt["key"] for prompt in prompts}
    assert {"translation", "assistant", "entity_extract", "event_extract", "relation_extract"} <= keys
    detail = (await client.get("/api/v1/ai/prompts/translation")).json()["data"]
    assert detail["active"]["version"] == 1
    assert "{{items_json}}" in detail["active"]["template"]

    created = await client.post("/api/v1/ai/prompts/translation/versions", json={
        "name": "翻译 v2",
        "template": "版本二\n{{items_json}}",
        "variables": ["items_json"],
        "description": "test",
    })
    assert created.status_code == 201
    assert created.json()["data"]["version"] == 2
    active = (await client.get("/api/v1/ai/prompts/translation")).json()["data"]["active"]
    assert active["version"] == 2
    activated = await client.post("/api/v1/ai/prompts/translation/activate/1")
    assert activated.json()["data"]["active_version"] == 1
    active = (await client.get("/api/v1/ai/prompts/translation")).json()["data"]["active"]
    assert active["version"] == 1


def test_log_redaction():
    from app.core.logging import redact

    assert "sk-1234567890" not in redact("Authorization: Bearer sk-1234567890abcdef")
    assert "secret" not in redact("api_key=secret").replace("api_key", "")
