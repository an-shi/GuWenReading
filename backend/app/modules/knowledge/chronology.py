"""Chinese historical chronology normalization.

The raw chronology text is never discarded. Conversion is only attempted when a
known era name (or explicit CE year) provides a real anchor; ambiguous era names
and bare 干支 years are deliberately left unknown.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

ERA_FILE = Path(__file__).resolve().parents[2] / "resources" / "chronology" / "era_names.txt"

DIGITS = {
    "零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
    "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
}
UNITS = {"十": 10, "百": 100, "千": 1000}
YEAR_TOKEN_RE = re.compile(r"(元|[〇零一二两三四五六七八九十百千0-9]{1,6})年")
CE_RE = re.compile(r"(?:公元|西元)\s*(\d{1,4})\s*年?")
MONTH_RE = re.compile(r"(?:闰)?[〇零一二三四五六七八九十0-9]{1,3}月")
DAY_RE = re.compile(r"(?:初[一二三四五六七八九十]|[〇零一二三四五六七八九十]{1,3}|[0-9]{1,2})日")
GANZHI = [f"{stem}{branch}" for stem in "甲乙丙丁戊己庚辛壬癸" for branch in "子丑寅卯辰巳午未申酉戌亥"]
DYNASTY_ALIASES = {
    "大唐": "唐", "李唐": "唐", "盛唐": "唐",
    "北宋": "宋", "南宋": "宋", "赵宋": "宋", "刘宋": "宋",
    "大元": "元", "大明": "明", "大清": "清",
    "蜀汉": "蜀汉", "季汉": "蜀汉",
    "曹魏": "魏", "孙吴": "吴", "东吴": "吴",
}


@dataclass
class ChronologyResult:
    year_start: int | None
    year_end: int | None
    precision: str
    era_name: str | None = None
    reign_year: str | None = None
    note: str | None = None


@lru_cache(maxsize=1)
def era_table() -> dict[str, list[tuple[str, int]]]:
    table: dict[str, list[tuple[str, int]]] = {}
    if not ERA_FILE.exists():
        return table
    for line in ERA_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|")
        if len(parts) != 3:
            continue
        dynasty, era, year = parts
        try:
            table.setdefault(era.strip(), []).append((dynasty.strip(), int(year)))
        except ValueError:
            continue
    return table


def normalize_dynasty(value: str | None) -> str | None:
    if not value:
        return None
    value = value.strip()
    for suffix in ("朝", "代", "国"):
        if value.endswith(suffix) and len(value) > len(suffix) + 1:
            value = value[: -len(suffix)]
    return DYNASTY_ALIASES.get(value, value)


def chinese_number(value: str) -> int | None:
    value = value.strip()
    if not value:
        return None
    if value == "元":
        return 1
    if value.isdigit():
        return int(value)
    total = 0
    current = 0
    for char in value:
        if char in DIGITS:
            current = DIGITS[char]
        elif char in UNITS:
            unit = UNITS[char]
            total += (current or 1) * unit
            current = 0
        else:
            return None
    return total + current


def _year_from_text_after(era: str, raw: str) -> str | None:
    index = raw.find(era)
    if index < 0:
        return None
    match = YEAR_TOKEN_RE.match(raw[index + len(era):].lstrip())
    return match.group(1) if match else None


def _candidate_years(
    era: str, year_token: str, dynasty: str | None
) -> tuple[int | None, str | None]:
    candidates = era_table().get(era, [])
    if not candidates:
        return None, f"未知年号：{era}"
    year_number = chinese_number(year_token)
    if year_number is None:
        return None, f"无法识别年号纪年：{year_token}"
    dynasty_name = normalize_dynasty(dynasty)
    if dynasty_name:
        filtered = [
            item for item in candidates
            if item[0] == dynasty_name or item[0] in dynasty_name or dynasty_name in item[0]
        ]
        if filtered:
            candidates = filtered
        elif len(candidates) > 1:
            return None, f"年号“{era}”无法与朝代“{dynasty}”匹配"
    unique_starts = {item[1] for item in candidates}
    if len(unique_starts) > 1:
        choices = "、".join(f"{d}{y}年" for d, y in candidates)
        return None, f"年号“{era}”存在多个起始年份（{choices}），需结合朝代或帝王确认"
    start = candidates[0][1]
    return start + year_number - 1, None


def _parse_single(
    raw: str, *, era_name: str | None, reign_year: str | None, dynasty: str | None
) -> ChronologyResult:
    text = raw.strip()
    ce_match = CE_RE.search(text)
    if ce_match:
        year = int(ce_match.group(1))
        return ChronologyResult(year, year, "year", note="原文为公元纪年")

    era = era_name.strip() if era_name else None
    token = None
    if era:
        token = _year_from_text_after(era, text)
        if token is None and reign_year:
            match = YEAR_TOKEN_RE.search(reign_year.strip())
            token = match.group(1) if match else None
        if token is None:
            token = "元"
    else:
        # Longest era names first to avoid matching a shorter suffix.
        for candidate in sorted(era_table(), key=len, reverse=True):
            if candidate in text:
                found = _year_from_text_after(candidate, text)
                if found:
                    era = candidate
                    token = found
                    break
    if era and token:
        year, note = _candidate_years(era, token, dynasty)
        if year is not None:
            precision = "year"
            if DAY_RE.search(text):
                precision = "day"
            elif MONTH_RE.search(text):
                precision = "month"
            return ChronologyResult(
                year, year, precision, era_name=era,
                reign_year=f"{token}年", note=note,
            )
        return ChronologyResult(None, None, "unknown", era_name=era, reign_year=f"{token}年", note=note)

    if any(ganzhi in text for ganzhi in GANZHI):
        return ChronologyResult(
            None, None, "unknown", note="仅有干支纪年，缺少年号或公元锚点，未强行换算"
        )
    return ChronologyResult(None, None, "unknown", note="未能识别可换算的纪年信息")


def parse_time(
    time_raw: str | None,
    *,
    era_name: str | None = None,
    reign_year: str | None = None,
    dynasty: str | None = None,
) -> ChronologyResult:
    raw = (time_raw or "").strip()
    if not raw and not (era_name and reign_year):
        return ChronologyResult(None, None, "unknown", note="原文未提供时间")

    # Ranges: split on 至/到 while requiring both halves to parse.
    if "至" in raw:
        left, right = raw.split("至", 1)
        first = _parse_single(
            left, era_name=era_name, reign_year=reign_year, dynasty=dynasty
        )
        second = _parse_single(
            right, era_name=first.era_name or era_name, reign_year=None, dynasty=dynasty
        )
        if first.year_start is not None and second.year_start is not None:
            return ChronologyResult(
                min(first.year_start, second.year_start),
                max(first.year_start, second.year_start),
                "range",
                era_name=first.era_name,
                reign_year=raw,
                note="原文为时间区间",
            )

    result = _parse_single(
        raw or f"{era_name or ''}{reign_year or ''}",
        era_name=era_name, reign_year=reign_year, dynasty=dynasty,
    )
    return result
