"""Translation task creation, editing and review endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_session, require_auth
from app.api.v1.schemas import (
    ManualTranslation, ReviewResolve, TranslateChapterRequest, TranslateSentenceRequest,
    TranslationEdit,
)
from app.core.errors import ErrorCode, AppError, not_found
from app.core.responses import ok
from app.core.utils import iso
from app.database.models import (
    Book, Chapter, Sentence, Translation, TranslationReview, TranslationVersion,
)
from app.modules.task_manager.service import serialize_task
from app.modules.translation.service import TranslationService

router = APIRouter(tags=["translations"], dependencies=[Depends(require_auth)])


def _translation_dict(translation: Translation) -> dict:
    return {
        "id": translation.id,
        "sentence_id": translation.sentence_id,
        "paragraph_id": translation.paragraph_id,
        "chapter_id": translation.chapter_id,
        "book_id": translation.book_id,
        "text": translation.text,
        "origin": translation.origin,
        "status": translation.status,
        "model_name": translation.model_name,
        "provider_name": translation.provider_name,
        "prompt_version": translation.prompt_version,
        "cache_key": translation.cache_key,
        "confidence": translation.confidence,
        "edited_at": iso(translation.edited_at),
        "version": translation.version,
        "created_at": iso(translation.created_at),
        "updated_at": iso(translation.updated_at),
    }


def _review_dict(review: TranslationReview) -> dict:
    return {
        "id": review.id,
        "translation_id": review.translation_id,
        "sentence_id": review.sentence_id,
        "candidate_text": review.candidate_text,
        "previous_text": review.previous_text,
        "reason": review.reason,
        "status": review.status,
        "model_name": review.model_name,
        "prompt_version": review.prompt_version,
        "cache_key": review.cache_key,
        "created_at": iso(review.created_at),
        "resolved_at": iso(review.resolved_at),
    }


async def _enqueue(request: Request, task) -> dict:
    request.app.state.task_runner.enqueue(task.id)
    return ok(serialize_task(task), message="queued")


@router.post("/translations/chapter/{chapter_id}", status_code=202)
async def translate_chapter(
    chapter_id: str,
    request: Request,
    body: TranslateChapterRequest = TranslateChapterRequest(),
    session: AsyncSession = Depends(get_session),
):
    service = TranslationService(
        request.app.state.settings, adapter_factory=request.app.state.adapter_factory
    )
    task = await service.create_chapter_task(
        session, chapter_id, model_id=body.model_id,
        retranslate=body.retranslate, only_failed=body.only_failed,
    )
    return await _enqueue(request, task)


@router.post("/translations/paragraph/{paragraph_id}", status_code=202)
async def translate_paragraph(
    paragraph_id: str,
    request: Request,
    body: TranslateSentenceRequest = TranslateSentenceRequest(),
    session: AsyncSession = Depends(get_session),
):
    service = TranslationService(request.app.state.settings)
    task = await service.create_paragraph_task(
        session, paragraph_id, model_id=body.model_id, retranslate=body.retranslate
    )
    return await _enqueue(request, task)


@router.post("/translations/sentence/{sentence_id}", status_code=202)
async def translate_sentence(
    sentence_id: str,
    request: Request,
    body: TranslateSentenceRequest = TranslateSentenceRequest(),
    session: AsyncSession = Depends(get_session),
):
    service = TranslationService(request.app.state.settings)
    task = await service.create_sentence_task(
        session, sentence_id, model_id=body.model_id, retranslate=body.retranslate
    )
    return await _enqueue(request, task)


@router.post("/translations/retranslate/{translation_id}", status_code=202)
async def retranslate(
    translation_id: str,
    request: Request,
    body: TranslateSentenceRequest = TranslateSentenceRequest(),
    session: AsyncSession = Depends(get_session),
):
    service = TranslationService(request.app.state.settings)
    task = await service.create_retranslate_task(
        session, translation_id, model_id=body.model_id
    )
    return await _enqueue(request, task)


@router.get("/translations/reviews")
async def list_reviews(
    request: Request,
    status: str = Query(default="pending", pattern="^(pending|accepted|rejected)$"),
    limit: int = Query(default=100, ge=1, le=500),
    session: AsyncSession = Depends(get_session),
):
    rows = await TranslationService(request.app.state.settings).list_reviews(
        session, status=status, limit=limit
    )
    for row in rows:
        row["created_at"] = iso(row["created_at"])
    return ok(rows)


@router.post("/translations/reviews/{review_id}/resolve")
async def resolve_review(
    review_id: str,
    body: ReviewResolve,
    request: Request,
    session: AsyncSession = Depends(get_session),
):
    review = await TranslationService(request.app.state.settings).resolve_review(
        session, review_id, action=body.action, text=body.text
    )
    return ok(_review_dict(review))


@router.post("/translations/{translation_id}/review")
async def resolve_translation_review(
    translation_id: str,
    body: ReviewResolve,
    request: Request,
    session: AsyncSession = Depends(get_session),
):
    review = await session.scalar(
        select(TranslationReview)
        .where(
            TranslationReview.translation_id == translation_id,
            TranslationReview.status == "pending",
        )
        .order_by(TranslationReview.created_at.desc())
    )
    if review is None:
        raise AppError(ErrorCode.NOT_FOUND, "No pending review for this translation", status_code=404)
    resolved = await TranslationService(request.app.state.settings).resolve_review(
        session, review.id, action=body.action, text=body.text
    )
    return ok(_review_dict(resolved))


@router.post("/translations/sentence/{sentence_id}/manual", status_code=201)
async def create_manual(
    sentence_id: str,
    body: ManualTranslation,
    request: Request,
    session: AsyncSession = Depends(get_session),
):
    translation = await TranslationService(request.app.state.settings).create_manual_translation(
        session, sentence_id, body.text
    )
    return ok(_translation_dict(translation))


@router.get("/translations/sentence/{sentence_id}")
async def get_sentence_translation(
    sentence_id: str,
    session: AsyncSession = Depends(get_session),
):
    sentence = await session.get(Sentence, sentence_id)
    if sentence is None:
        raise not_found("Sentence", sentence_id)
    chapter = await session.get(Chapter, sentence.chapter_id)
    book = await session.get(Book, sentence.book_id)
    translation = await session.scalar(
        select(Translation).where(Translation.sentence_id == sentence_id)
    )
    reviews = list((await session.scalars(
        select(TranslationReview)
        .where(TranslationReview.sentence_id == sentence_id)
        .order_by(TranslationReview.created_at.desc())
    )).all())
    versions = []
    if translation is not None:
        versions = list((await session.scalars(
            select(TranslationVersion)
            .where(TranslationVersion.translation_id == translation.id)
            .order_by(TranslationVersion.created_at.desc())
        )).all())
    return ok({
        "sentence": {
            "id": sentence.id,
            "original_text": sentence.original_text,
            "translation_state": sentence.translation_state,
            "translation_error": sentence.translation_error,
            "book_id": sentence.book_id,
            "chapter_id": sentence.chapter_id,
            "paragraph_id": sentence.paragraph_id,
        },
        "book_title": book.title if book else None,
        "chapter_title": chapter.title if chapter else None,
        "translation": _translation_dict(translation) if translation else None,
        "versions": [
            {
                "id": version.id,
                "text": version.text,
                "origin": version.origin,
                "model_name": version.model_name,
                "prompt_version": version.prompt_version,
                "note": version.note,
                "created_at": iso(version.created_at),
            }
            for version in versions
        ],
        "reviews": [_review_dict(review) for review in reviews],
    })


@router.get("/translations/{translation_id}")
async def get_translation(
    translation_id: str,
    session: AsyncSession = Depends(get_session),
):
    translation = await session.get(Translation, translation_id)
    if translation is None:
        raise not_found("Translation", translation_id)
    sentence = await session.get(Sentence, translation.sentence_id)
    return ok({
        "translation": _translation_dict(translation),
        "sentence": {
            "id": sentence.id,
            "original_text": sentence.original_text,
        } if sentence else None,
    })


@router.put("/translations/{translation_id}")
async def edit_translation(
    translation_id: str,
    body: TranslationEdit,
    request: Request,
    session: AsyncSession = Depends(get_session),
):
    translation = await TranslationService(request.app.state.settings).edit_translation(
        session, translation_id, body.text, note=body.note
    )
    return ok(_translation_dict(translation), message="manual edit saved")


@router.get("/translations/{translation_id}/versions")
async def get_versions(
    translation_id: str,
    session: AsyncSession = Depends(get_session),
):
    versions = list((await session.scalars(
        select(TranslationVersion)
        .where(TranslationVersion.translation_id == translation_id)
        .order_by(TranslationVersion.created_at.desc())
    )).all())
    return ok([
        {
            "id": version.id,
            "text": version.text,
            "origin": version.origin,
            "model_name": version.model_name,
            "prompt_version": version.prompt_version,
            "note": version.note,
            "created_at": iso(version.created_at),
        }
        for version in versions
    ])
