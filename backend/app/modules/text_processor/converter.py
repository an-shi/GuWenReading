"""Traditional/simplified conversion helpers.

Conversion never writes back to 原文. The reader may request a display variant,
but the stored original and sentence rows keep their exact characters.
"""

from __future__ import annotations

from functools import lru_cache

try:  # Optional dependency: degrade gracefully if unavailable.
    from opencc import OpenCC  # type: ignore
except Exception:  # pragma: no cover - dependency present in production
    OpenCC = None  # type: ignore


@lru_cache(maxsize=2)
def _converter(direction: str):
    if OpenCC is None:
        return None
    config = "t2s" if direction == "simplified" else "s2t"
    try:
        return OpenCC(config)
    except Exception:
        return None


def to_simplified(text: str) -> str:
    converter = _converter("simplified")
    return converter.convert(text) if converter else text


def to_traditional(text: str) -> str:
    converter = _converter("traditional")
    return converter.convert(text) if converter else text


def convert(text: str, variant: str) -> str:
    if variant == "simplified":
        return to_simplified(text)
    if variant == "traditional":
        return to_traditional(text)
    return text
