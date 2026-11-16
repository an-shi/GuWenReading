"""Unified API envelope helpers."""

from __future__ import annotations

from typing import Any, Generic, TypeVar

from pydantic import BaseModel, Field

T = TypeVar("T")


def ok(data: Any = None, message: str = "success") -> dict[str, Any]:
    return {"success": True, "data": data, "message": message}


class ErrorBody(BaseModel):
    code: str
    message: str
    details: Any | None = None


def fail(code: str, message: str, details: Any | None = None) -> dict[str, Any]:
    return {
        "success": False,
        "data": None,
        "message": message,
        "error": ErrorBody(code=code, message=message, details=details).model_dump(),
    }


class Page(BaseModel, Generic[T]):
    items: list[T]
    total: int
    page: int = Field(default=1, ge=1)
    page_size: int = Field(default=20, ge=1)


def page_data(items: list[Any], total: int, page: int, page_size: int) -> dict[str, Any]:
    return {"items": items, "total": total, "page": page, "page_size": page_size}
