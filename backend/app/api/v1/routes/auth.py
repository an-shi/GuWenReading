"""Account and device administration for server mode."""

from __future__ import annotations

import re

from fastapi import APIRouter, Depends, Request
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_optional_user, get_security, get_session, require_auth
from app.api.v1.schemas import DeviceRegister, LoginRequest, RegisterRequest
from app.core.errors import AppError, ErrorCode
from app.core.responses import ok
from app.core.security import hash_password, verify_password
from app.core.utils import iso, new_id, utcnow
from app.database.models import Device, User

router = APIRouter(tags=["auth"])
USERNAME_RE = re.compile(r"^[A-Za-z0-9_\-\u4e00-\u9fff.]{2,100}$")


def _user_dict(user: User) -> dict:
    return {
        "id": user.id,
        "username": user.username,
        "display_name": user.display_name,
        "created_at": iso(user.created_at),
    }


@router.post("/auth/register")
async def register(
    body: RegisterRequest,
    request: Request,
    session: AsyncSession = Depends(get_session),
    current_user: User | None = Depends(get_optional_user),
):
    username = body.username.strip()
    if not USERNAME_RE.match(username):
        raise AppError(ErrorCode.VALIDATION_ERROR, "Username contains unsupported characters", status_code=422)
    count = await session.scalar(select(func.count()).select_from(User)) or 0
    if count > 0 and current_user is None:
        raise AppError(
            ErrorCode.FORBIDDEN,
            "An account already exists; ask the owner to create additional accounts",
            status_code=403,
        )
    existing = await session.scalar(select(User).where(User.username == username))
    if existing is not None:
        raise AppError(ErrorCode.CONFLICT, "Username already exists", status_code=409)
    user = User(
        id=new_id(),
        username=username,
        display_name=(body.display_name or username).strip(),
        password_hash=hash_password(body.password),
    )
    session.add(user)
    await session.commit()
    security = get_security(request)
    token = security.create_token(user.id, user.username)
    return ok({"token": token, "token_type": "bearer", "user": _user_dict(user)})


@router.post("/auth/login")
async def login(
    body: LoginRequest,
    request: Request,
    session: AsyncSession = Depends(get_session),
):
    user = await session.scalar(select(User).where(User.username == body.username.strip()))
    if user is None or not verify_password(body.password, user.password_hash):
        raise AppError(ErrorCode.AUTH_INVALID, "Incorrect username or password", status_code=401)
    security = get_security(request)
    token = security.create_token(user.id, user.username)
    return ok({"token": token, "token_type": "bearer", "user": _user_dict(user)})


@router.get("/auth/me")
async def me(user: User | None = Depends(require_auth)):
    if user is None:
        return ok({"authenticated": False, "local_mode": True})
    return ok({"authenticated": True, "user": _user_dict(user)})


devices_router = APIRouter(tags=["devices"], dependencies=[Depends(require_auth)])


def _device_dict(device: Device) -> dict:
    return {
        "id": device.id,
        "name": device.name,
        "platform": device.platform,
        "fingerprint": device.fingerprint,
        "app_version": device.app_version,
        "last_seen_at": iso(device.last_seen_at),
        "is_current": device.is_current,
        "created_at": iso(device.created_at),
    }


@devices_router.get("/devices")
async def list_devices(session: AsyncSession = Depends(get_session)):
    rows = list((await session.scalars(
        select(Device).where(Device.deleted_at.is_(None)).order_by(Device.last_seen_at.desc())
    )).all())
    return ok([_device_dict(device) for device in rows])


@devices_router.post("/devices/register")
async def register_device(
    body: DeviceRegister,
    session: AsyncSession = Depends(get_session),
    user: User | None = Depends(require_auth),
):
    device = None
    if body.fingerprint:
        device = await session.scalar(
            select(Device).where(Device.fingerprint == body.fingerprint)
        )
    if device is None:
        device = Device(
            id=new_id(),
            name=body.name,
            platform=body.platform,
            fingerprint=body.fingerprint,
            app_version=body.app_version,
            user_id=user.id if user else None,
        )
        session.add(device)
    else:
        device.name = body.name
        device.platform = body.platform
        device.app_version = body.app_version
        device.deleted_at = None
        device.version += 1
        if user is not None:
            device.user_id = user.id
    device.last_seen_at = utcnow()
    await session.commit()
    await session.refresh(device)
    return ok(_device_dict(device))


@devices_router.delete("/devices/{device_id}")
async def delete_device(device_id: str, session: AsyncSession = Depends(get_session)):
    device = await session.get(Device, device_id)
    if device is None or device.deleted_at is not None:
        raise AppError(ErrorCode.NOT_FOUND, "Device not found", status_code=404)
    device.deleted_at = utcnow()
    device.version += 1
    await session.commit()
    return ok({"id": device.id, "removed": True})
