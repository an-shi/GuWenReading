"""WebSocket task progress stream."""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from app.core.errors import AppError

router = APIRouter()


@router.websocket("/ws/tasks")
async def task_stream(websocket: WebSocket):
    settings = websocket.app.state.settings
    if settings.auth_required:
        token = websocket.query_params.get("token")
        if not token:
            await websocket.close(code=4401, reason="authentication required")
            return
        try:
            websocket.app.state.security.decode_token(token)
        except AppError:
            await websocket.close(code=4401, reason="invalid token")
            return

    await websocket.accept()
    broker = websocket.app.state.task_broker
    queue = broker.subscribe()
    try:
        await websocket.send_json({
            "type": "connected",
            "timestamp": datetime.now(UTC).isoformat(),
        })
        while True:
            try:
                event = await asyncio.wait_for(queue.get(), timeout=25)
            except TimeoutError:
                event = {
                    "type": "heartbeat",
                    "timestamp": datetime.now(UTC).isoformat(),
                }
            await websocket.send_json(event)
    except (WebSocketDisconnect, RuntimeError):
        pass
    finally:
        broker.unsubscribe(queue)
