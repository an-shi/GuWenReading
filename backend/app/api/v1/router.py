"""Aggregate /api/v1 routers."""

from fastapi import APIRouter

from app.api.v1.routes import (
    ai, assistant, auth, books, chapters, knowledge, reading, sync, system, tasks,
    translations,
)

api_router = APIRouter(prefix="/api/v1")
api_router.include_router(system.router)
api_router.include_router(auth.router)
api_router.include_router(auth.devices_router)
api_router.include_router(books.router)
api_router.include_router(chapters.router)
api_router.include_router(translations.router)
api_router.include_router(tasks.router)
api_router.include_router(ai.router)
api_router.include_router(reading.router)
api_router.include_router(knowledge.router)
api_router.include_router(assistant.router)
api_router.include_router(sync.router)
