"""API dependency helpers."""

from __future__ import annotations

from typing import AsyncIterator

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.errors import AppError, ErrorCode
from app.core.security import SecurityManager
from app.database.models import User

bearer = HTTPBearer(auto_error=False)


def get_settings_dep(request: Request) -> Settings:
    return request.app.state.settings


def get_security(request: Request) -> SecurityManager:
    return request.app.state.security


def get_broker(request: Request):
    return request.app.state.task_broker


def get_task_runner(request: Request):
    return request.app.state.task_runner


async def get_session(request: Request) -> AsyncIterator[AsyncSession]:
    factory = request.app.state.session_factory
    async with factory() as session:
        try:
            yield session
        except Exception:
            await session.rollback()
            raise


async def get_optional_user(
    request: Request,
    session: AsyncSession = Depends(get_session),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
) -> User | None:
    if credentials is None or not credentials.credentials:
        return None
    security: SecurityManager = request.app.state.security
    payload = security.decode_token(credentials.credentials)
    user = await session.get(User, str(payload.get("sub")))
    if user is None:
        raise AppError(ErrorCode.AUTH_INVALID, "User no longer exists", status_code=401)
    return user


async def require_auth(
    request: Request,
    session: AsyncSession = Depends(get_session),
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
) -> User | None:
    settings: Settings = request.app.state.settings
    if not settings.auth_required:
        return None
    if credentials is None or not credentials.credentials:
        raise AppError(ErrorCode.AUTH_REQUIRED, "Authentication required", status_code=401)
    security: SecurityManager = request.app.state.security
    payload = security.decode_token(credentials.credentials)
    user = await session.get(User, str(payload.get("sub")))
    if user is None:
        raise AppError(ErrorCode.AUTH_INVALID, "User no longer exists", status_code=401)
    return user
