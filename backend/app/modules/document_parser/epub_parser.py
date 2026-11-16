"""EPUB parser: spine order, TOC titles and embedded cover."""

from __future__ import annotations

import posixpath
import re
from pathlib import Path

from bs4 import BeautifulSoup

from app.modules.document_parser.base import (
    ChapterBlock, DocumentParseError, DocumentParser, ParsedDocument, clean_paragraphs,
)
from app.modules.document_parser.metadata import filename_title, metadata_from_mapping

BLOCK_TAGS = ["h1", "h2", "h3", "h4", "h5", "h6", "p", "blockquote", "li", "div", "pre", "td"]


def _flatten_toc(entries, prefix: str = "") -> dict[str, str]:
    mapping: dict[str, str] = {}
    for entry in entries:
        if isinstance(entry, tuple):
            section, children = entry
            href = getattr(section, "href", "") or ""
            title = getattr(section, "title", "") or ""
            if href:
                clean = href.split("#", 1)[0]
                mapping[posixpath.normpath(clean)] = title.strip() or prefix
                mapping[posixpath.basename(clean)] = title.strip() or prefix
            mapping.update(_flatten_toc(children, title))
        else:
            href = getattr(entry, "href", "") or ""
            title = getattr(entry, "title", "") or ""
            if href:
                clean = href.split("#", 1)[0]
                mapping[posixpath.normpath(clean)] = title.strip()
                mapping[posixpath.basename(clean)] = title.strip()
    return mapping


def _extract_blocks(html: bytes) -> list[str]:
    import warnings

    from bs4 import XMLParsedAsHTMLWarning

    with warnings.catch_warnings():
        warnings.simplefilter("ignore", XMLParsedAsHTMLWarning)
        soup = BeautifulSoup(html, "lxml")
    for tag in soup(["script", "style", "nav"]):
        tag.decompose()
    for br in soup.find_all("br"):
        br.replace_with("\n")
    body = soup.body or soup
    selected = []
    for element in body.find_all(BLOCK_TAGS):
        if element.find(BLOCK_TAGS):
            continue
        text = element.get_text()
        if text and text.strip():
            selected.append(text)
    if not selected:
        text = body.get_text("\n")
        return [line.strip() for line in text.splitlines() if line.strip()]
    paragraphs: list[str] = []
    for text in selected:
        for piece in text.split("\n"):
            piece = re.sub(r"[ \t\u00a0]+", " ", piece).strip()
            if piece:
                paragraphs.append(piece)
    return paragraphs


class EpubParser(DocumentParser):
    format = "epub"
    extensions = (".epub",)

    def parse(self, path: Path, filename: str) -> ParsedDocument:
        try:
            import ebooklib
            from ebooklib import epub
        except ImportError as exc:  # pragma: no cover
            raise DocumentParseError("EPUB support is not installed") from exc

        try:
            book = epub.read_epub(str(path))
        except Exception as exc:
            raise DocumentParseError(f"EPUB could not be opened: {exc}") from exc

        def dc(name: str) -> str | None:
            values = book.get_metadata("DC", name)
            return str(values[0][0]).strip() if values else None

        metadata = metadata_from_mapping(
            title=dc("title") or filename_title(filename),
            author=dc("creator"),
            extra={
                "language": dc("language"), "publisher": dc("publisher"),
                "identifier": dc("identifier"), "date": dc("date"),
            },
        )
        toc_map = _flatten_toc(book.toc)
        chapters: list[ChapterBlock] = []
        warnings: list[str] = []
        nav_items = {item.get_name() for item in book.get_items_of_type(ebooklib.ITEM_NAVIGATION)}

        for idref, _linear in book.spine:
            item = book.get_item_with_id(idref)
            if item is None:
                continue
            if item.get_type() not in (ebooklib.ITEM_DOCUMENT,):
                continue
            name = item.get_name()
            if name in nav_items:
                continue
            paragraphs = _extract_blocks(item.get_content())
            if not paragraphs:
                continue
            heading = None
            if len(paragraphs[0]) <= 80 and not re.search(r"[，。！？；]", paragraphs[0]):
                # Only treat the first line as a heading when it looks like one.
                if re.match(r"^(第.+[章回节卷篇]|卷.+|序|前言|后记|附录|尾声)", paragraphs[0]):
                    heading = paragraphs.pop(0)
            title = (
                toc_map.get(posixpath.normpath(name))
                or toc_map.get(posixpath.basename(name))
                or heading
                or f"第 {len(chapters) + 1} 部分"
            )
            chapters.append(
                ChapterBlock(title=title[:400], paragraphs=clean_paragraphs(paragraphs), source_title=heading)
            )

        if not chapters:
            raise DocumentParseError("EPUB contains no readable spine documents")
        if len(chapters) == 1:
            warnings.append("EPUB has a single spine document; chapter structure follows the file")

        cover: bytes | None = None
        for item in book.get_items():
            properties = getattr(item, "properties", None)
            if properties is None and hasattr(item, "get_properties"):
                properties = item.get_properties()
            properties = properties or []
            if item.get_type() == ebooklib.ITEM_COVER or "cover-image" in properties:
                try:
                    content = item.get_content()
                    if 0 < len(content) <= 8 * 1024 * 1024:
                        cover = content
                        break
                except Exception:
                    continue

        return ParsedDocument(
            format=self.format, chapters=chapters, metadata=metadata,
            cover=cover, warnings=warnings,
        )
