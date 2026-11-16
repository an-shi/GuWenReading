"""Prompt files, database versioning and safe template rendering."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.errors import AppError, ErrorCode
from app.core.logging import get_logger
from app.database.models import PromptTemplate

logger = get_logger(__name__)
# Historical brands found in previously seeded prompt templates.
LEGACY_BRANDS = ("GuWenAI", "GuWenReading")
PLACEHOLDER_RE = re.compile(r"\{\{\s*([a-zA-Z0-9_]+)\s*\}\}")


@dataclass
class PromptFile:
    key: str
    version: int
    name: str
    description: str
    template: str
    variables: list[str]
    path: Path


@dataclass
class PromptContent:
    key: str
    version: int
    name: str
    template: str


def parse_prompt_file(path: Path) -> PromptFile | None:
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---"):
        return None
    parts = text.split("---", 2)
    if len(parts) < 3:
        return None
    header, template = parts[1], parts[2].lstrip("\n")
    meta: dict[str, str] = {}
    for line in header.splitlines():
        if not line.strip() or line.strip().startswith("#"):
            continue
        key, _, value = line.partition(":")
        meta[key.strip()] = value.strip()
    if "key" not in meta:
        return None
    try:
        version = int(meta.get("version", path.stem.lstrip("v")))
    except ValueError:
        version = 1
    variables = [
        item.strip() for item in meta.get("variables", "").split(",") if item.strip()
    ]
    return PromptFile(
        key=meta["key"],
        version=version,
        name=meta.get("name", meta["key"]),
        description=meta.get("description", ""),
        template=template,
        variables=variables,
        path=path,
    )


def load_prompt_catalog(settings: Settings) -> dict[str, list[PromptFile]]:
    catalog: dict[str, list[PromptFile]] = {}
    root = settings.prompts_dir
    if not root.exists():
        logger.warning("prompt_directory_missing", path=str(root))
        return catalog
    for path in sorted(root.glob("*/v*.md")):
        parsed = parse_prompt_file(path)
        if parsed is None:
            logger.warning("prompt_file_invalid", path=str(path))
            continue
        catalog.setdefault(parsed.key, []).append(parsed)
    for values in catalog.values():
        values.sort(key=lambda item: item.version)
    return catalog


async def seed_prompts(session: AsyncSession, settings: Settings) -> int:
    """Install bundled prompts only for keys that have no versions yet."""
    def rebrand_text(value: str | None) -> str | None:
        if not value:
            return value
        for brand in (*LEGACY_BRANDS, settings.app_name):
            value = value.replace(f" {brand} ", settings.app_name)
            value = value.replace(f" {brand}", settings.app_name)
            value = value.replace(f"{brand} ", settings.app_name)
        for brand in LEGACY_BRANDS:
            value = value.replace(brand, settings.app_name)
        return value

    rebranded_count = 0
    for prompt in (await session.scalars(select(PromptTemplate))).all():
        template = rebrand_text(prompt.template)
        name = rebrand_text(prompt.name)
        description = rebrand_text(prompt.description)
        if (template, name, description) != (prompt.template, prompt.name, prompt.description):
            prompt.template = template or prompt.template
            prompt.name = name or prompt.name
            prompt.description = description
            rebranded_count += 1
    if rebranded_count:
        await session.commit()
        logger.info("prompts_rebranded", count=rebranded_count)
    catalog = load_prompt_catalog(settings)
    existing = set((await session.scalars(select(PromptTemplate.key))).all())
    inserted = 0
    for key, files in catalog.items():
        if key in existing or not files:
            continue
        latest = files[-1]
        session.add(PromptTemplate(
            key=latest.key,
            version=latest.version,
            name=latest.name,
            description=latest.description,
            template=latest.template,
            variables=latest.variables,
            is_active=True,
        ))
        inserted += 1
    if inserted:
        await session.commit()
        logger.info("prompts_seeded", count=inserted)
    return inserted


async def get_active_prompt(session: AsyncSession, settings: Settings, key: str) -> PromptContent:
    row = await session.scalar(
        select(PromptTemplate)
        .where(PromptTemplate.key == key, PromptTemplate.is_active.is_(True))
        .order_by(PromptTemplate.version.desc())
    )
    if row is not None:
        return PromptContent(key=row.key, version=row.version, name=row.name, template=row.template)
    catalog = load_prompt_catalog(settings)
    if key in catalog and catalog[key]:
        latest = catalog[key][-1]
        return PromptContent(
            key=latest.key, version=latest.version, name=latest.name, template=latest.template
        )
    raise AppError(ErrorCode.NOT_FOUND, f"Prompt not found: {key}", status_code=404)


def render_prompt(template: str, variables: dict[str, object]) -> str:
    missing: set[str] = set()

    def replace(match: re.Match[str]) -> str:
        name = match.group(1)
        if name not in variables:
            missing.add(name)
            return match.group(0)
        value = variables[name]
        if value is None:
            return ""
        return str(value)

    rendered = PLACEHOLDER_RE.sub(replace, template)
    if missing:
        raise AppError(
            ErrorCode.VALIDATION_ERROR,
            f"Prompt is missing variables: {', '.join(sorted(missing))}",
            status_code=500,
        )
    return rendered


async def list_prompts(session: AsyncSession) -> list[PromptTemplate]:
    return list((await session.scalars(
        select(PromptTemplate).order_by(PromptTemplate.key, PromptTemplate.version.desc())
    )).all())


async def create_prompt_version(
    session: AsyncSession,
    *,
    key: str,
    name: str,
    template: str,
    variables: list[str],
    description: str | None = None,
) -> PromptTemplate:
    if not template.strip():
        raise AppError(ErrorCode.VALIDATION_ERROR, "Prompt template cannot be empty", status_code=422)
    current = await session.scalar(
        select(PromptTemplate).where(PromptTemplate.key == key).order_by(PromptTemplate.version.desc())
    )
    version = (current.version + 1) if current else 1
    if current:
        current.is_active = False
    row = PromptTemplate(
        key=key,
        version=version,
        name=name,
        description=description,
        template=template,
        variables=variables,
        is_active=True,
    )
    session.add(row)
    await session.commit()
    await session.refresh(row)
    return row
