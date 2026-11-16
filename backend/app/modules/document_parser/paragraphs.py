"""Shared paragraph/chapter assembly for plain-text-like sources."""

from __future__ import annotations

from app.modules.document_parser.base import ChapterBlock, clean_paragraphs
from app.modules.document_parser.chapter_detector import split_lines_into_chapters


def _join_wrapped(left: str, right: str) -> str:
    if not left:
        return right
    left_char = left[-1]
    right_char = right[0]
    cjk = lambda char: "\u3400" <= char <= "\u9fff" or char in "，。！？；：“”‘’、（）《》"
    if cjk(left_char) or cjk(right_char):
        return left + right
    return left + " " + right


def lines_to_paragraphs(lines: list[str]) -> list[str]:
    has_blank_lines = any(not line.strip() for line in lines)
    if not has_blank_lines:
        # Common in Chinese ebooks: one physical line is one paragraph.
        return [line.strip() for line in lines if line.strip()]

    paragraphs: list[str] = []
    buffer = ""
    for line in lines:
        value = line.strip()
        if not value:
            if buffer:
                paragraphs.append(buffer)
                buffer = ""
            continue
        buffer = _join_wrapped(buffer, value)
    if buffer:
        paragraphs.append(buffer)
    return clean_paragraphs(paragraphs)


def build_chapters(lines: list[str], default_title: str) -> list[ChapterBlock]:
    raw = split_lines_into_chapters(lines, default_title=default_title)
    chapters: list[ChapterBlock] = []
    pending_titles: list[str] = []

    for title, body in raw:
        paragraphs = lines_to_paragraphs(body)
        paragraphs = clean_paragraphs(paragraphs)
        if not paragraphs:
            # A volume heading immediately followed by a chapter heading.
            pending_titles.append(title)
            continue
        full_title = title
        if pending_titles:
            full_title = " · ".join(pending_titles + [title])
            pending_titles = []
        chapters.append(ChapterBlock(title=full_title[:400], paragraphs=paragraphs))

    if pending_titles:
        if chapters:
            chapters[-1].title = (" · ".join(pending_titles) + " · " + chapters[-1].title)[:400]
        elif lines:
            chapters.append(
                ChapterBlock(
                    title=" · ".join(pending_titles)[:400],
                    paragraphs=lines_to_paragraphs(lines),
                )
            )
    if not chapters and lines:
        paragraphs = lines_to_paragraphs(lines)
        if paragraphs:
            chapters.append(ChapterBlock(title=default_title, paragraphs=paragraphs))
    return chapters
