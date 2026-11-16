"""Parser registry and content-based format detection."""

from __future__ import annotations

import zipfile
from pathlib import Path

from app.core.errors import AppError, ErrorCode
from app.modules.document_parser.base import DocumentParseError, DocumentParser, ParsedDocument
from app.modules.document_parser.docx_parser import DocxParser
from app.modules.document_parser.epub_parser import EpubParser
from app.modules.document_parser.pdf_parser import PdfParser
from app.modules.document_parser.txt_parser import TxtParser

_PARSERS: dict[str, DocumentParser] = {
    parser.format: parser for parser in (TxtParser(), EpubParser(), DocxParser(), PdfParser())
}

SUPPORTED_FORMATS = tuple(_PARSERS.keys())


def normalize_format(filename: str) -> str:
    suffix = Path(filename).suffix.lower().lstrip(".")
    if suffix not in _PARSERS:
        raise AppError(
            ErrorCode.UNSUPPORTED_FORMAT,
            f"Unsupported file format: {suffix or 'unknown'}. Supported: TXT, EPUB, DOCX, PDF",
            status_code=415,
        )
    return suffix


def detect_format(path: Path, filename: str) -> str:
    """Inspect file bytes first; fall back to the extension for plain text."""
    try:
        with path.open("rb") as handle:
            head = handle.read(8)
    except OSError as exc:
        raise AppError(ErrorCode.PARSE_ERROR, f"Cannot read uploaded file: {exc}") from exc

    extension = Path(filename).suffix.lower().lstrip(".")
    if head.startswith(b"%PDF-"):
        return "pdf"
    if head.startswith(b"PK\x03\x04") and zipfile.is_zipfile(path):
        try:
            with zipfile.ZipFile(path) as archive:
                names = set(archive.namelist())
                if "mimetype" in names:
                    try:
                        if archive.read("mimetype").strip() == b"application/epub+zip":
                            return "epub"
                    except KeyError:
                        pass
                if "word/document.xml" in names:
                    return "docx"
                if any(name.endswith((".xhtml", ".html")) for name in names):
                    return "epub"
        except zipfile.BadZipFile as exc:
            raise AppError(ErrorCode.PARSE_ERROR, "Damaged ZIP-based document") from exc
        raise AppError(
            ErrorCode.UNSUPPORTED_FORMAT,
            "ZIP archive is not a supported EPUB or DOCX document",
            status_code=415,
        )
    if extension == "pdf":
        raise AppError(ErrorCode.PARSE_ERROR, "File extension is PDF but content is not a PDF")
    if extension in {"epub", "docx"}:
        raise AppError(
            ErrorCode.PARSE_ERROR,
            f"File extension is {extension.upper()} but content is not a valid {extension.upper()} file",
        )
    if extension in {"txt", ""}:
        return "txt"
    # Content is plain text even though the extension is unfamiliar.
    raise AppError(
        ErrorCode.UNSUPPORTED_FORMAT,
        f"Unsupported file format: {extension}. Supported: TXT, EPUB, DOCX, PDF",
        status_code=415,
    )


def get_parser(filename: str) -> DocumentParser:
    return _PARSERS[normalize_format(filename)]


def parse_document(path: Path, filename: str) -> ParsedDocument:
    parser = get_parser(filename)
    try:
        return parser.parse(path, filename)
    except DocumentParseError as exc:
        raise AppError(ErrorCode.PARSE_ERROR, str(exc), status_code=422) from exc
    except AppError:
        raise
    except Exception as exc:
        raise AppError(
            ErrorCode.PARSE_ERROR, f"Failed to parse {filename}: {exc}", status_code=422
        ) from exc
