"""AI reading assistant endpoint."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_session, require_auth
from app.api.v1.schemas import AssistantChatRequest
from app.core.responses import ok
from app.modules.assistant.service import AssistantService

router = APIRouter(tags=["assistant"], dependencies=[Depends(require_auth)])


@router.post("/assistant/chat")
async def assistant_chat(
    body: AssistantChatRequest,
    request: Request,
    session: AsyncSession = Depends(get_session),
):
    service = AssistantService(
        request.app.state.settings, adapter_factory=request.app.state.adapter_factory
    )
    result = await service.chat(
        session,
        question=body.question,
        book_id=body.book_id,
        chapter_id=body.chapter_id,
        paragraph_id=body.paragraph_id,
        sentence_id=body.sentence_id,
        session_id=body.session_id,
        model_id=body.model_id,
    )
    return ok(result)
