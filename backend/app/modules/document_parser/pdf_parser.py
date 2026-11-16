"""Text-based PDF parser.

Scanned PDFs are detected explicitly and rejected with an actionable message;
OCR is a documented future capability rather than a silent failure.
"""

from __future__ import annotations

import re
from pathlib import Path

from pypdf import PdfReader

from app.modules.document_parser.base import (
    ChapterBlock, DocumentParseError, DocumentParser, ParsedDocument, clean_paragraphs,
)
from app.modules.document_parser.chapter_detector import is_chapter_heading
from app.modules.document_parser.metadata import filename_title, metadata_from_mapping

PAGE_NUMBER_RE = re.compile(r"^\s*[-—]?\s*[0-9ivxlcIVXLC]{1,6}\s*[-—]?\s*$")
TERMINAL = "。！？；!?;…”’」』）)"
CJK_BOUNDARY = re.compile(r"[\u3400-\u9fff，。！？；：“”‘’、（）《》]")


def _join(left: str, right: str) -> str:
    if not left:
        return right
    if CJK_BOUNDARY.match(left[-1]) or CJK_BOUNDARY.match(right[0]):
        return left + right
    return left + " " + right


def _group_page_text(pages: list[str]) -> list[str]:
    lines: list[str] = []
    for page in pages:
        for raw in page.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
            line = raw.strip()
            if not line or PAGE_NUMBER_RE.match(line):
                continue
            lines.append(line)

    paragraphs: list[str] = []
    buffer = ""
    for index, line in enumerate(lines):
        next_line = lines[index + 1] if index + 1 < len(lines) else ""
        buffer = _join(buffer, line)
        ends_sentence = buffer.endswith(tuple(TERMINAL))
        heading_next = is_chapter_heading(next_line)
        if heading_next or (ends_sentence and len(buffer) >= 40):
            paragraphs.append(buffer)
            buffer = ""
    if buffer:
        paragraphs.append(buffer)
    return clean_paragraphs(paragraphs)


class PdfParser(DocumentParser):
    format = "pdf"
    extensions = (".pdf",)

    def parse(self, path: Path, filename: str) -> ParsedDocument:
        try:
            reader = PdfReader(str(path))
        except Exception as exc:
            raise DocumentParseError(f"PDF could not be opened: {exc}") from exc
        if reader.is_encrypted:
            try:
                if reader.decrypt("") == 0:
                    raise DocumentParseError("PDF is password protected")
            except Exception as exc:
                raise DocumentParseError("PDF is password protected") from exc

        pages: list[str] = []
        for page in reader.pages:
            try:
                pages.append(page.extract_text() or "")
            except Exception:
                pages.append("")
        raw_length = sum(len(page.strip()) for page in pages)
        if raw_length < 20:
            raise DocumentParseError(
                "PDF has no extractable text (likely a scanned document). OCR is not supported yet."
            )

        info = reader.metadata or {}
        metadata = metadata_from_mapping(
            title=(str(info.get("/Title", "") or "")).strip() or filename_title(filename),
            author=(str(info.get("/Author", "") or "")).strip() or None,
            extra={"page_count": len(reader.pages), "pdf_producer": str(info.get("/Producer", "") or "")},
        )

        # Build chapter boundaries from raw lines, then group body text.
        all_lines: list[str] = []
        for page in pages:
            for raw in page.splitlines():
                line = raw.strip()
                if line and not PAGE_NUMBER_RE.match(line):
                    all_lines.append(line)

        chapters: list[ChapterBlock] = []
        current_title = metadata["title"] or filename_title(filename)
        current_lines: list[str] = []

        def flush() -> None:
            nonlocal current_lines, current_title
            if not current_lines:
                return
            paragraphs = _group_page_text(["\n".join(current_lines)])
            if paragraphs:
                chapters.append(ChapterBlock(title=current_title[:400], paragraphs=paragraphs))
            current_lines = []

        for line in all_lines:
            if is_chapter_heading(line):
                flush()
                current_title = line
            else:
                current_lines.append(line)
        flush()

        if not chapters:
            raise DocumentParseError("No readable text found in PDF")

        return ParsedDocument(
            format=self.format,
            chapters=chapters,
            metadata=metadata,
            warnings=["Scanned image content inside the PDF is ignored"],
        )
