"""Backend application factory."""

from __future__ import annotations

import time
import uuid
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy.exc import IntegrityError
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.api.v1.router import api_router
from app.api.ws import router as ws_router
from app.ai.prompts import seed_prompts
from app.ai.providers.registry import AdapterFactory
from app.core.config import Settings
from app.core.errors import AppError, ErrorCode
from app.core.logging import configure_logging, get_logger
from app.core.responses import fail, ok
from app.core.security import SecurityManager
from app.database.session import (
    create_schema, make_engine, make_session_factory,
)
from app.modules.knowledge.extraction import make_extraction_handler
from app.modules.task_manager import TaskEventBroker, TaskRunner
from app.modules.translation.service import make_translation_handler

logger = get_logger(__name__)


def create_app(
    settings: Settings | None = None,
    adapter_factory: AdapterFactory | None = None,
) -> FastAPI:
    settings = settings or Settings()
    settings.ensure_directories()
    configure_logging(settings.log_level, settings.log_json)

    engine = make_engine(settings)
    session_factory = make_session_factory(engine)
    security = SecurityManager(settings)
    broker = TaskEventBroker()
    runner = TaskRunner(session_factory, settings, broker)
    runner.register("translation", make_translation_handler(settings, adapter_factory))
    runner.register("knowledge_extraction", make_extraction_handler(settings, adapter_factory))

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        if settings.auto_create_schema:
            app.state.fts_available = await create_schema(engine)
        async with session_factory() as session:
            await seed_prompts(session, settings)
            if app.state.fts_available:
                from app.database.fts import backfill_fts

                indexed = await backfill_fts(session)
                if indexed:
                    logger.info("search_index_backfilled", documents=indexed)
        await runner.start()
        logger.info(
            "backend_started", mode=settings.mode, data_dir=str(settings.data_dir),
            auth_required=settings.auth_required,
        )
        try:
            yield
        finally:
            await runner.stop()
            await engine.dispose()
            logger.info("backend_stopped")

    app = FastAPI(
        title="古文阅读器 API",
        version=settings.version,
        description=(
            "AI-assisted classical Chinese reading, translation and historical knowledge service. "
            "All endpoints use a unified success/error envelope."
        ),
        lifespan=lifespan,
        docs_url="/docs",
        redoc_url=None,
    )
    app.state.settings = settings
    app.state.engine = engine
    app.state.session_factory = session_factory
    app.state.security = security
    app.state.task_broker = broker
    app.state.task_runner = runner
    app.state.fts_available = False
    app.state.adapter_factory = adapter_factory

    origins = settings.cors_origin_list or ["*"]
    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.middleware("http")
    async def request_context(request: Request, call_next):
        request_id = request.headers.get("x-request-id") or uuid.uuid4().hex[:16]
        request.state.request_id = request_id
        started = time.perf_counter()
        response = await call_next(request)
        elapsed = round((time.perf_counter() - started) * 1000, 1)
        response.headers["X-Request-ID"] = request_id
        logger.info(
            "http_request", method=request.method, path=request.url.path,
            status=response.status_code, duration_ms=elapsed, request_id=request_id,
        )
        return response

    @app.exception_handler(AppError)
    async def app_error_handler(_request: Request, exc: AppError):
        return JSONResponse(
            status_code=exc.status_code,
            content=fail(exc.code, exc.message, exc.details),
        )

    @app.exception_handler(RequestValidationError)
    async def validation_handler(_request: Request, exc: RequestValidationError):
        return JSONResponse(
            status_code=422,
            content=fail(
                ErrorCode.VALIDATION_ERROR, "Request validation failed",
                jsonable_encoder(exc.errors()),
            ),
        )

    @app.exception_handler(IntegrityError)
    async def integrity_handler(_request: Request, exc: IntegrityError):
        logger.warning("database_integrity_error", error=str(exc.orig))
        return JSONResponse(
            status_code=409,
            content=fail(ErrorCode.CONFLICT, "The operation conflicts with existing data"),
        )

    @app.exception_handler(StarletteHTTPException)
    async def http_handler(_request: Request, exc: StarletteHTTPException):
        code = ErrorCode.NOT_FOUND if exc.status_code == 404 else ErrorCode.UNKNOWN
        return JSONResponse(
            status_code=exc.status_code,
            content=fail(code, str(exc.detail)),
        )

    @app.exception_handler(Exception)
    async def unhandled_handler(request: Request, exc: Exception):
        logger.exception(
            "unhandled_exception", path=request.url.path,
            request_id=getattr(request.state, "request_id", None),
        )
        return JSONResponse(
            status_code=500,
            content=fail(ErrorCode.UNKNOWN, "Internal server error"),
        )

    app.include_router(api_router)
    app.include_router(ws_router)

    @app.get("/", include_in_schema=False)
    async def root():
        return ok({
            "name": settings.app_name,
            "version": settings.version,
            "docs": "/docs",
            "api": "/api/v1",
        })

    return app


__all__ = ["create_app"]
