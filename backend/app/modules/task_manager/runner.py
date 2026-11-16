"""Background task runner with cancellation, persistence and progress events."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from typing import Any, Awaitable, Callable

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.core.config import Settings
from app.core.logging import get_logger
from app.core.utils import utcnow
from app.database.models import Task
from app.modules.task_manager.broker import TaskEventBroker
from app.modules.task_manager.service import FINAL_STATUSES, serialize_task

logger = get_logger(__name__)


class TaskCancelled(Exception):
    pass


@dataclass
class TaskContext:
    session: AsyncSession
    task: Task
    broker: TaskEventBroker
    cancel_event: asyncio.Event

    async def progress(
        self,
        *,
        completed: int | None = None,
        total: int | None = None,
        failed: int | None = None,
        progress: float | None = None,
        result: dict[str, Any] | None = None,
    ) -> None:
        if total is not None:
            self.task.total = total
        if completed is not None:
            self.task.completed = completed
        if failed is not None:
            self.task.failed_count = failed
        if progress is not None:
            self.task.progress = max(0.0, min(100.0, progress))
        elif self.task.total:
            processed = self.task.completed + self.task.failed_count
            self.task.progress = round(min(100.0, processed / self.task.total * 100), 2)
        if result is not None:
            self.task.result = result
        self.task.updated_at = utcnow()
        await self.session.commit()
        await self.broker.publish({"type": "task_progress", "task": serialize_task(self.task)})

    def raise_if_cancelled(self) -> None:
        if self.cancel_event.is_set() or self.task.cancel_requested:
            raise TaskCancelled()

    async def check_cancel(self) -> None:
        # The flag may be set by another HTTP session.
        await self.session.refresh(self.task, attribute_names=["cancel_requested"])
        self.raise_if_cancelled()


TaskHandler = Callable[[AsyncSession, Task, TaskContext], Awaitable[dict[str, Any]]]


class TaskRunner:
    def __init__(
        self,
        session_factory: async_sessionmaker[AsyncSession],
        settings: Settings,
        broker: TaskEventBroker,
    ) -> None:
        self.session_factory = session_factory
        self.settings = settings
        self.broker = broker
        self.handlers: dict[str, TaskHandler] = {}
        self.queue: asyncio.Queue[str] = asyncio.Queue()
        self._workers: list[asyncio.Task] = []
        self._cancel_events: dict[str, asyncio.Event] = {}
        self._running = True

    def register(self, task_type: str, handler: TaskHandler) -> None:
        self.handlers[task_type] = handler

    async def start(self) -> None:
        self._running = True
        for index in range(max(1, self.settings.task_workers)):
            self._workers.append(asyncio.create_task(self._worker(index), name=f"task-worker-{index}"))
        await self.recover()

    async def stop(self) -> None:
        self._running = False
        for worker in self._workers:
            worker.cancel()
        await asyncio.gather(*self._workers, return_exceptions=True)
        self._workers.clear()

    async def recover(self) -> int:
        async with self.session_factory() as session:
            rows = list((await session.scalars(
                select(Task).where(Task.status.in_(["queued", "running"])).order_by(Task.created_at)
            )).all())
            for task in rows:
                if task.status == "running":
                    task.status = "queued"
                    task.error = None
                task.updated_at = utcnow()
            await session.commit()
            for task in rows:
                self.enqueue(task.id)
        if rows:
            logger.info("tasks_recovered", count=len(rows))
        return len(rows)

    def enqueue(self, task_id: str) -> None:
        self.queue.put_nowait(task_id)

    async def cancel(self, task_id: str) -> Task:
        async with self.session_factory() as session:
            task = await session.get(Task, task_id)
            if task is None:
                from app.core.errors import AppError, ErrorCode

                raise AppError(ErrorCode.NOT_FOUND, "Task not found", status_code=404)
            if task.status in FINAL_STATUSES:
                return task
            task.cancel_requested = True
            task.updated_at = utcnow()
            if task.status == "queued":
                task.status = "cancelled"
                task.finished_at = utcnow()
            await session.commit()
            event = self._cancel_events.get(task_id)
            if event:
                event.set()
            await self.broker.publish({
                "type": "task_cancelled" if task.status == "cancelled" else "task_progress",
                "task": serialize_task(task),
            })
            await session.refresh(task)
            return task

    async def _worker(self, index: int) -> None:
        while self._running:
            try:
                task_id = await self.queue.get()
            except asyncio.CancelledError:
                break
            try:
                await self._run_one(task_id)
            except asyncio.CancelledError:
                break
            except Exception:  # pragma: no cover - defensive
                logger.exception("task_worker_error", worker=index)
            finally:
                self.queue.task_done()

    async def _run_one(self, task_id: str) -> None:
        async with self.session_factory() as session:
            task = await session.get(Task, task_id)
            if task is None or task.status in FINAL_STATUSES:
                return
            if task.cancel_requested:
                task.status = "cancelled"
                task.finished_at = utcnow()
                await session.commit()
                await self.broker.publish({"type": "task_cancelled", "task": serialize_task(task)})
                return
            handler = self.handlers.get(task.type)
            if handler is None:
                task.status = "failed"
                task.error = f"No handler registered for task type {task.type}"
                task.finished_at = utcnow()
                await session.commit()
                await self.broker.publish({"type": "task_failed", "task": serialize_task(task)})
                return

            task.status = "running"
            task.started_at = utcnow()
            task.error = None
            await session.commit()
            await self.broker.publish({"type": "task_started", "task": serialize_task(task)})

            cancel_event = asyncio.Event()
            self._cancel_events[task_id] = cancel_event
            context = TaskContext(
                session=session, task=task, broker=self.broker, cancel_event=cancel_event
            )
            try:
                result = await handler(session, task, context) or {}
                await session.refresh(task)
                status = str(result.get("status") or "completed")
                if status not in {"completed", "partial", "failed"}:
                    status = "completed"
                task.status = status
                task.result = result
                task.finished_at = utcnow()
                if task.total and status != "failed":
                    task.progress = max(task.progress, round(
                        min(1.0, (task.completed + task.failed_count) / task.total) * 100, 2
                    ))
                await session.commit()
                event_type = "task_failed" if status == "failed" else "task_completed"
                await self.broker.publish({"type": event_type, "task": serialize_task(task)})
                logger.info("task_finished", task_id=task_id, type=task.type, status=status)
            except TaskCancelled:
                await session.rollback()
                task = await session.get(Task, task_id)
                if task is not None:
                    task.status = "cancelled"
                    task.finished_at = utcnow()
                    await session.commit()
                    await self.broker.publish({"type": "task_cancelled", "task": serialize_task(task)})
            except Exception as exc:
                await session.rollback()
                task = await session.get(Task, task_id)
                if task is not None:
                    task.status = "failed"
                    task.error = str(exc)[:4000]
                    task.finished_at = utcnow()
                    await session.commit()
                    await self.broker.publish({"type": "task_failed", "task": serialize_task(task)})
                logger.exception("task_failed", task_id=task_id, type=task.type)
            finally:
                self._cancel_events.pop(task_id, None)
