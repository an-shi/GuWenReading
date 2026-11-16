"""Task management endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_session, get_task_runner, require_auth
from app.core.responses import ok, page_data
from app.modules.task_manager.service import get_task, list_tasks, serialize_task

router = APIRouter(tags=["tasks"], dependencies=[Depends(require_auth)])


@router.get("/tasks")
async def get_tasks(
    status: str | None = Query(default=None),
    type: str | None = Query(default=None),
    book_id: str | None = Query(default=None),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
    session: AsyncSession = Depends(get_session),
):
    tasks, total = await list_tasks(
        session, status=status, task_type=type, book_id=book_id,
        page=page, page_size=page_size,
    )
    return ok(page_data([serialize_task(task) for task in tasks], total, page, page_size))


@router.get("/tasks/{task_id}")
async def task_detail(task_id: str, session: AsyncSession = Depends(get_session)):
    return ok(serialize_task(await get_task(session, task_id)))


@router.post("/tasks/{task_id}/cancel")
async def cancel_task(task_id: str, request: Request):
    task = await get_task_runner(request).cancel(task_id)
    return ok(serialize_task(task))


@router.get("/tasks/{task_id}/progress")
async def task_progress(task_id: str, session: AsyncSession = Depends(get_session)):
    task = await get_task(session, task_id)
    payload = serialize_task(task)
    return ok({
        "id": task.id,
        "status": task.status,
        "progress": payload["progress"],
        "total": task.total,
        "completed": task.completed,
        "failed_count": task.failed_count,
        "cancel_requested": task.cancel_requested,
        "result": task.result or {},
        "error": task.error,
    })
