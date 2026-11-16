"""Deterministic metadata heuristics.

We deliberately avoid guessing a title from arbitrary first-line prose: a wrong
title is worse than a filename. Explicit markers (《...》, 书名：) and embedded
document metadata take priority.
"""

from __future__ import annotations

import re
from pathlib import Path

TITLE_MARK_RE = re.compile(r"《([^》]{1,60})》")
AUTHOR_RE = re.compile(r"(?:作者|著者|撰者|撰)\s*[：:]\s*(.{1,40})")
DYNASTY_RE = re.compile(r"(?:朝代|时代|朝)\s*[：:]\s*(.{1,30})")
AUTHOR_FILE_RE = re.compile(r"[（(]([^）)]{2,20})[）)]\s*$")


def filename_title(filename: str) -> str:
    stem = Path(filename).stem
    stem = re.sub(r"[_\s]+", " ", stem).strip()
    stem = re.sub(r"\s*[-—]\s*.*$", "", stem).strip()
    stem = TITLE_MARK_RE.sub(lambda m: m.group(1), stem)
    return stem[:200] or "未命名古籍"


def guess_metadata(filename: str, sample: str) -> dict:
    title = filename_title(filename)
    author: str | None = None
    dynasty: str | None = None

    lines = [line.strip() for line in sample.splitlines() if line.strip()][:12]
    for line in lines:
        if not author:
            match = AUTHOR_RE.search(line)
            if match:
                author = match.group(1).strip(" ，,。")
        if not dynasty:
            match = DYNASTY_RE.search(line)
            if match:
                dynasty = match.group(1).strip(" ，,。")

    # A 《title》 marker is an explicit title signal.
    for line in lines[:4]:
        match = TITLE_MARK_RE.search(line)
        if match and not re.search(r"[，。！？；]", line):
            title = match.group(1).strip()
            break

    if not author:
        match = AUTHOR_FILE_RE.search(Path(filename).stem)
        if match:
            author = match.group(1)

    return {
        "title": title,
        "author": author,
        "dynasty": dynasty,
        "extra": {},
    }


def metadata_from_mapping(*, title: str | None, author: str | None, extra: dict | None = None) -> dict:
    return {
        "title": (title or "").strip()[:200] or None,
        "author": (author or "").strip()[:200] or None,
        "dynasty": None,
        "extra": extra or {},
    }
