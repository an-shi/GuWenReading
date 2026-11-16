"""DOCX parser preserving paragraph order, headings and tables."""

from __future__ import annotations

from pathlib import Path

from docx import Document
from docx.oxml.ns import qn
from docx.table import Table
from docx.text.paragraph import Paragraph

from app.modules.document_parser.base import (
    ChapterBlock, DocumentParseError, DocumentParser, ParsedDocument, clean_paragraphs,
)
from app.modules.document_parser.chapter_detector import is_chapter_heading
from app.modules.document_parser.metadata import filename_title, metadata_from_mapping


def _is_heading(paragraph: Paragraph) -> bool:
    style = (paragraph.style.name or "") if paragraph.style is not None else ""
    return bool(
        style.lower().startswith(("heading", "标题")) or is_chapter_heading(paragraph.text)
    )


class DocxParser(DocumentParser):
    format = "docx"
    extensions = (".docx",)

    def parse(self, path: Path, filename: str) -> ParsedDocument:
        try:
            document = Document(str(path))
        except Exception as exc:
            raise DocumentParseError(f"DOCX could not be opened: {exc}") from exc

        props = document.core_properties
        metadata = metadata_from_mapping(
            title=(props.title or "").strip() or filename_title(filename),
            author=(props.author or "").strip() or None,
            extra={"subject": props.subject, "created": str(props.created) if props.created else None},
        )

        blocks: list[tuple[str, bool]] = []
        body = document.element.body
        for child in body.iterchildren():
            if child.tag == qn("w:p"):
                paragraph = Paragraph(child, document)
                text = paragraph.text.strip()
                if text:
                    blocks.append((text, _is_heading(paragraph)))
            elif child.tag == qn("w:tbl"):
                table = Table(child, document)
                for row in table.rows:
                    cells = [cell.text.strip().replace("\n", " ") for cell in row.cells]
                    line = "\t".join(cell for cell in cells if cell)
                    if line:
                        blocks.append((line, False))

        chapters: list[ChapterBlock] = []
        current_title: str | None = None
        current: list[str] = []

        def flush() -> None:
            nonlocal current_title, current
            paragraphs = clean_paragraphs(current)
            if paragraphs:
                chapters.append(
                    ChapterBlock(title=(current_title or metadata["title"] or filename_title(filename))[:400], paragraphs=paragraphs)
                )
            current = []

        for text, heading in blocks:
            if heading:
                flush()
                current_title = text
            else:
                current.append(text)
        flush()

        if not chapters:
            raise DocumentParseError("DOCX contains no readable text")

        return ParsedDocument(format=self.format, chapters=chapters, metadata=metadata)
