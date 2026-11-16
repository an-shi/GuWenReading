"""Domain error types and stable error codes."""

from __future__ import annotations

from typing import Any


class ErrorCode:
    VALIDATION_ERROR = "VALIDATION_ERROR"
    NOT_FOUND = "NOT_FOUND"
    CONFLICT = "CONFLICT"
    DUPLICATE_BOOK = "DUPLICATE_BOOK"
    UNSUPPORTED_FORMAT = "UNSUPPORTED_FORMAT"
    PARSE_ERROR = "PARSE_ERROR"
    FILE_TOO_LARGE = "FILE_TOO_LARGE"
    TRANSLATION_NOT_CONFIGURED = "TRANSLATION_NOT_CONFIGURED"
    PROVIDER_ERROR = "PROVIDER_ERROR"
    PROVIDER_NOT_FOUND = "PROVIDER_NOT_FOUND"
    MODEL_NOT_FOUND = "MODEL_NOT_FOUND"
    AI_INVALID_RESPONSE = "AI_INVALID_RESPONSE"
    TASK_NOT_CANCELLABLE = "TASK_NOT_CANCELLABLE"
    AUTH_REQUIRED = "AUTH_REQUIRED"
    AUTH_INVALID = "AUTH_INVALID"
    FORBIDDEN = "FORBIDDEN"
    SYNC_DISABLED = "SYNC_DISABLED"
    SYNC_CONFLICT = "SYNC_CONFLICT"
    MANUAL_TRANSLATION_PROTECTED = "MANUAL_TRANSLATION_PROTECTED"
    REPARSE_BLOCKED = "REPARSE_BLOCKED"
    UNKNOWN = "UNKNOWN_ERROR"


class AppError(Exception):
    def __init__(
        self,
        code: str,
        message: str,
        *,
        status_code: int = 400,
        details: Any | None = None,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.status_code = status_code
        self.details = details


def not_found(entity: str, entity_id: str | None = None) -> AppError:
    suffix = f": {entity_id}" if entity_id else ""
    return AppError(ErrorCode.NOT_FOUND, f"{entity} not found{suffix}", status_code=404)


def validation_error(message: str, details: Any | None = None) -> AppError:
    return AppError(ErrorCode.VALIDATION_ERROR, message, status_code=422, details=details)
