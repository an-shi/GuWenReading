"""Run the backend: python -m app [--host HOST] [--port PORT]."""

from __future__ import annotations

import argparse

import uvicorn

from app.core.config import Settings


def main() -> None:
    settings = Settings()
    parser = argparse.ArgumentParser(description="古文阅读器后端")
    parser.add_argument("--host", default=settings.host)
    parser.add_argument("--port", type=int, default=settings.port)
    parser.add_argument("--reload", action="store_true")
    args = parser.parse_args()
    uvicorn.run(
        "app.main:create_app",
        factory=True,
        host=args.host,
        port=args.port,
        reload=args.reload,
        log_level=settings.log_level.lower(),
    )


if __name__ == "__main__":
    main()
