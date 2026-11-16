"""Sentence segmentation for classical Chinese.

The splitter is punctuation-aware but conservative:
* terminal punctuation is kept with its sentence, along with trailing closing
  quotes and ellipsis runs;
* extremely long comma-only clauses are split only near their middle and are
  flagged for review;
* every span carries character offsets into the managed extracted text;
* no character of the source (apart from surrounding whitespace) is dropped.
"""

from __future__ import annotations

from dataclasses import dataclass

TERMINALS = set("。！？；!?;…")
TRAILING = TERMINALS | set("”’」』）)】》〉\"'")
OPEN_QUOTES = set("“‘「『（(【《〈")
CLOSE_QUOTES = set("”’」』）)】》〉")
COMMA_BREAKS = set("，、：,:")


@dataclass(frozen=True)
class SentenceSpan:
    text: str
    start: int
    end: int
    needs_review: bool
    confidence: float


def _is_dot_terminal(text: str, index: int) -> bool:
    if text[index] != ".":
        return False
    before = text[index - 1] if index > 0 else ""
    after = text[index + 1] if index + 1 < len(text) else ""
    return not before.isdigit() and (not after or after.isspace())


def _long_clause_split(text: str, start: int, end: int) -> list[tuple[int, int]]:
    """Split very long clauses at a comma near the middle; never at a quote."""
    if end - start <= 320:
        return [(start, end)]
    middle = start + (end - start) // 2
    candidates = [
        index for index in range(start + 80, end - 20)
        if text[index] in COMMA_BREAKS
    ]
    if not candidates:
        return [(start, end)]
    chosen = min(candidates, key=lambda index: abs(index - middle))
    left = _long_clause_split(text, start, chosen + 1)
    right = _long_clause_split(text, chosen + 1, end)
    return left + right


def split_sentences(text: str, base_offset: int = 0) -> list[SentenceSpan]:
    if not text or not text.strip():
        return []

    length = len(text)
    boundary: list[tuple[int, int, float]] = []
    seg_start = 0
    index = 0
    while index < length:
        char = text[index]
        is_terminal = char in TERMINALS or _is_dot_terminal(text, index)
        if not is_terminal:
            index += 1
            continue
        end = index + 1
        # Keep ellipsis runs, repeated punctuation, closing quotes and spaces.
        while end < length and (
            text[end] in TRAILING or text[end] in " \t\u3000"
        ):
            end += 1
        boundary.append((seg_start, end, 1.0))
        seg_start = end
        index = end

    if seg_start < length:
        boundary.append((seg_start, length, 0.8 if length - seg_start < 24 else 0.55))

    spans: list[tuple[int, int, float]] = []
    for left, right, confidence in boundary:
        for part_left, part_right in _long_clause_split(text, left, right):
            segment = text[part_left:part_right]
            if not segment.strip():
                continue
            if len(text[part_left:part_right].strip()) > 320:
                confidence = min(confidence, 0.6)
            elif part_right - part_left != right - left:
                confidence = min(confidence, 0.6)
            spans.append((part_left, part_right, confidence))

    # Trim whitespace and merge punctuation-only / one-character fragments.
    normalised: list[tuple[int, int, float]] = []
    for left, right, confidence in spans:
        while left < right and text[left].isspace():
            left += 1
        while right > left and text[right - 1].isspace():
            right -= 1
        if left >= right:
            continue
        content = text[left:right]
        punctuation_only = all(
            (not char.strip()) or char in TERMINALS or char in CLOSE_QUOTES
            for char in content
        )
        if normalised and (len(content) <= 1 or punctuation_only or content[0] in CLOSE_QUOTES):
            prev_left, _prev_right, prev_confidence = normalised[-1]
            normalised[-1] = (prev_left, right, min(prev_confidence, confidence))
            continue
        normalised.append((left, right, confidence))

    if not normalised and text.strip():
        left = len(text) - len(text.lstrip())
        right = len(text.rstrip())
        normalised = [(left, right, 0.5)]

    quote_balance = sum(1 for char in text if char in OPEN_QUOTES) - sum(
        1 for char in text if char in CLOSE_QUOTES
    )
    unbalanced = quote_balance != 0

    result: list[SentenceSpan] = []
    for left, right, confidence in normalised:
        if unbalanced:
            confidence = min(confidence, 0.7)
        needs_review = confidence < 0.75
        result.append(
            SentenceSpan(
                text=text[left:right],
                start=base_offset + left,
                end=base_offset + right,
                needs_review=needs_review,
                confidence=round(confidence, 2),
            )
        )
    return result
