"""Parser contracts shared by every supported book format."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path


class DocumentParseError(Exception):
    pass


@dataclass
class ChapterBlock:
    title: str
    paragraphs: list[str]
    source_title: str | None = None


@dataclass
class ParsedDocument:
    format: str
    chapters: list[ChapterBlock]
    metadata: dict = field(default_factory=dict)
    cover: bytes | None = None
    warnings: list[str] = field(default_factory=list)


class DocumentParser:
    format = "unknown"
    extensions: tuple[str, ...] = ()

    def parse(self, path: Path, filename: str) -> ParsedDocument:  # pragma: no cover - interface
        raise NotImplementedError


def clean_paragraphs(paragraphs: list[str]) -> list[str]:
    cleaned: list[str] = []
    for paragraph in paragraphs:
        value = paragraph.replace("\r\n", "\n").replace("\r", "\n").replace("\x00", "")
        value = value.strip()
        if value:
            cleaned.append(value)
    return cleaned
