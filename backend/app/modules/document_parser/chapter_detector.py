"""Classical Chinese document chapter segmentation.

Handles common heading styles while refusing to treat ordinary prose that merely
starts with 第... as a heading (a maximum length and punctuation check applies).
"""

from __future__ import annotations

import re

CHAPTER_PATTERNS = [
    re.compile(r"^第[〇零一二三四五六七八九十百千万两0-9０-９]+[卷回章节篇部集](?:\s|$|[：:、.．·]|.{0,24}$)"),
    re.compile(r"^卷[〇零一二三四五六七八九十百千0-9]+(?:\s|$|[：:、.．]|.{0,20}$)"),
    re.compile(r"^[上下中]卷(?:\s|$)"),
    re.compile(r"^[序跋志表传纪世家列传本纪书志]{1,4}[一二三四五六七八九十]*$"),
    re.compile(r"^(?:序言|前言|自序|后序|后记|附录|凡例|目录|楔子|引子|尾声)$"),
    re.compile(r"^#{1,3}\s+\S+"),
    re.compile(r"^(?:第\s*)?[0-9]{1,4}[、.．]\s*\S{2,30}$"),
]

_TERMINAL = "。！？；!?;…"
MAX_HEADING_LEN = 42


def is_chapter_heading(line: str) -> bool:
    value = line.strip().lstrip("\ufeff")
    if not value or len(value) > MAX_HEADING_LEN:
        return False
    # Headings never end with a sentence-break comma/period pattern.
    if value.endswith(("。", "，", "！", "？", "；")):
        return False
    if value.startswith(("　", "  ")) and len(value) > 16:
        return False
    return any(pattern.match(value) for pattern in CHAPTER_PATTERNS)


def first_heading_index(lines: list[str], start: int = 0) -> int | None:
    for index in range(start, len(lines)):
        if is_chapter_heading(lines[index]):
            return index
    return None


def split_lines_into_chapters(
    lines: list[str],
    *,
    default_title: str,
    source_title: str | None = None,
) -> list[tuple[str, list[str]]]:
    """Return (title, lines) pairs; content before the first heading becomes 卷首."""
    headings: list[int] = [i for i, line in enumerate(lines) if is_chapter_heading(line)]
    if not headings:
        return [(default_title, lines)]

    chapters: list[tuple[str, list[str]]] = []
    if headings[0] > 0:
        preface = lines[: headings[0]]
        if any(line.strip() for line in preface):
            chapters.append((f"{source_title or default_title}·卷首", preface))

    for position, start in enumerate(headings):
        end = headings[position + 1] if position + 1 < len(headings) else len(lines)
        title = lines[start].strip().lstrip("#").strip()
        body = lines[start + 1 : end]
        chapters.append((title[:400] or default_title, body))
    return chapters


def heading_title_from_lines(lines: list[str]) -> str | None:
    for line in lines[:6]:
        value = line.strip()
        if value and is_chapter_heading(value):
            return value.lstrip("#").strip()
    return None
