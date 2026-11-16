"""Task serialization and CRUD."""

from __future__ import annotations

from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import ErrorCode, AppError
from app.core.utils import iso
from app.database.models import Task

ACTIVE_STATUSES = {"queued", "running"}
FINAL_STATUSES = {"completed", "partial", "failed", "cancelled"}


def serialize_task(task: Task) -> dict[str, Any]:
    return {
        "id": task.id,
        "type": task.type,
        "status": task.status,
        "title": task.title,
        "progress": round(task.progress, 2),
        "total": task.total,
        "completed": task.completed,
        "failed_count": task.failed_count,
        "payload": task.payload or {},
        "result": task.result or {},
        "error": task.error,
        "cancel_requested": task.cancel_requested,
        "book_id": task.book_id,
        "chapter_id": task.chapter_id,
        "created_at": iso(task.created_at),
        "started_at": iso(task.started_at),
        "finished_at": iso(task.finished_at),
        "updated_at": iso(task.updated_at),
    }


async def create_task(
    session: AsyncSession,
    *,
    task_type: str,
    title: str,
    payload: dict[str, Any] | None = None,
    book_id: str | None = None,
    chapter_id: str | None = None,
    total: int = 0,
) -> Task:
    task = Task(
        type=task_type,
        title=title[:300],
        payload=payload or {},
        book_id=book_id,
        chapter_id=chapter_id,
        total=total,
        status="queued",
    )
    session.add(task)
    await session.commit()
    await session.refresh(task)
    return task


async def get_task(session: AsyncSession, task_id: str) -> Task:
    task = await session.get(Task, task_id)
    if task is None:
        raise AppError(ErrorCode.NOT_FOUND, "Task not found", status_code=404)
    return task


async def list_tasks(
    session: AsyncSession,
    *,
    status: str | None = None,
    task_type: str | None = None,
    book_id: str | None = None,
    page: int = 1,
    page_size: int = 20,
) -> tuple[list[Task], int]:
    conditions = []
    if status:
        conditions.append(Task.status == status)
    if task_type:
        conditions.append(Task.type == task_type)
    if book_id:
        conditions.append(Task.book_id == book_id)
    total = await session.scalar(select(func.count()).select_from(Task).where(*conditions)) or 0
    rows = list((await session.scalars(
        select(Task).where(*conditions).order_by(Task.created_at.desc())
        .offset((page - 1) * page_size).limit(page_size)
    )).all())
    return rows, total
