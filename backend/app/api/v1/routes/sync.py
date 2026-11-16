"""Synchronization HTTP endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_session, require_auth
from app.api.v1.schemas import SyncPushRequest
from app.core.responses import ok
from app.modules.sync.service import SyncService

router = APIRouter(tags=["sync"], dependencies=[Depends(require_auth)])


@router.get("/sync/status")
async def sync_status(
    request: Request,
    device_id: str = Query(min_length=1),
    session: AsyncSession = Depends(get_session),
):
    service = SyncService(request.app.state.settings)
    return ok(await service.status(session, device_id))


@router.post("/sync/push")
async def sync_push(
    body: SyncPushRequest,
    request: Request,
    session: AsyncSession = Depends(get_session),
):
    service = SyncService(request.app.state.settings)
    return ok(await service.push(session, body.device_id, body.operations))


@router.get("/sync/pull")
async def sync_pull(
    request: Request,
    device_id: str = Query(min_length=1),
    after: int = Query(default=0, ge=0),
    limit: int = Query(default=200, ge=1, le=1000),
    session: AsyncSession = Depends(get_session),
):
    service = SyncService(request.app.state.settings)
    return ok(await service.pull(session, device_id, after=after, limit=limit))


@router.get("/sync/conflicts")
async def sync_conflicts(
    request: Request,
    limit: int = Query(default=100, ge=1, le=500),
    session: AsyncSession = Depends(get_session),
):
    service = SyncService(request.app.state.settings)
    return ok(await service.conflicts(session, limit=limit))


@router.post("/sync/conflicts/{seq}/resolve")
async def sync_resolve(
    seq: int,
    request: Request,
    action: str = Query(pattern="^(accept_client|accept_server)$"),
    session: AsyncSession = Depends(get_session),
):
    service = SyncService(request.app.state.settings)
    return ok(await service.resolve_conflict(session, seq, action))
