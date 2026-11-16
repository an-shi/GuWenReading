"""Import every ORM model so metadata and Alembic see the full schema."""

from app.database.base import Base
from app.database.models.ai import (
    AIModel, AIProvider, AssistantMessage, AssistantSession, Glossary, PromptTemplate,
    Task, Translation, TranslationCache, TranslationReview, TranslationVersion,
)
from app.database.models.knowledge import (
    EntityMention, EntityRelation, EventParticipant, EventSource, HistoricalEntity,
    HistoricalEvent, RelationSource,
)
from app.database.models.library import Book, Chapter, Paragraph, Sentence
from app.database.models.reading import (
    Annotation, Bookmark, Device, ReadingProgress, User,
)
from app.database.models.sync import SyncCursor, SyncOperation

__all__ = [
    "Base", "Book", "Chapter", "Paragraph", "Sentence", "Translation",
    "TranslationVersion", "TranslationReview", "TranslationCache", "AIProvider",
    "AIModel", "PromptTemplate", "Task", "AssistantSession", "AssistantMessage",
    "Glossary", "Annotation", "Bookmark", "ReadingProgress", "Device", "User",
    "HistoricalEntity", "EntityMention", "EntityRelation", "RelationSource",
    "HistoricalEvent", "EventParticipant", "EventSource", "SyncOperation", "SyncCursor",
]
