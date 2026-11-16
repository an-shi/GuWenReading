"""Structured logging with mandatory secret redaction."""

from __future__ import annotations

import logging
import re
import sys

import structlog

_SECRET_PATTERNS = [
    re.compile(r"(sk-[A-Za-z0-9_\-]{8,})"),
    re.compile(r"(?i)(api[_-]?key\s*[=:]\s*)[^\s,;\"']+"),
    re.compile(r"(?i)(authorization:\s*bearer\s+)[^\s\"']+"),
    re.compile(r"(?i)(bearer\s+)[A-Za-z0-9._\-]{16,}"),
]


def redact(value: str) -> str:
    result = value
    for pattern in _SECRET_PATTERNS:
        if pattern.groups:
            result = pattern.sub(lambda m: m.group(1) + "***", result)
        else:
            result = pattern.sub("***", result)
    return result


def _redact_processor(_logger, _method, event_dict):
    for key, value in list(event_dict.items()):
        if isinstance(value, str):
            event_dict[key] = redact(value)
        elif key.lower() in {"api_key", "authorization", "secret", "token"}:
            event_dict[key] = "***"
    return event_dict


def configure_logging(level: str = "INFO", json_logs: bool = False) -> None:
    logging.basicConfig(
        format="%(message)s",
        stream=sys.stdout,
        level=getattr(logging, level.upper(), logging.INFO),
        force=True,
    )
    renderer = (
        structlog.processors.JSONRenderer(ensure_ascii=False)
        if json_logs
        else structlog.dev.ConsoleRenderer(colors=False)
    )
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso", utc=True),
            _redact_processor,
            renderer,
        ],
        wrapper_class=structlog.make_filtering_bound_logger(
            getattr(logging, level.upper(), logging.INFO)
        ),
        logger_factory=structlog.PrintLoggerFactory(),
        cache_logger_on_first_use=True,
    )


def get_logger(name: str = "guwenreading"):
    return structlog.get_logger(name)
