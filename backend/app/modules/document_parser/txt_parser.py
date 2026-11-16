"""TXT parser with encoding detection and structure inference."""

from __future__ import annotations

from pathlib import Path

from charset_normalizer import from_bytes

from app.modules.document_parser.base import DocumentParseError, DocumentParser, ParsedDocument
from app.modules.document_parser.metadata import guess_metadata
from app.modules.document_parser.paragraphs import build_chapters


def decode_bytes(data: bytes) -> tuple[str, str]:
    if data.startswith(b"\xef\xbb\xbf"):
        return data.decode("utf-8-sig"), "utf-8-sig"
    if data.startswith((b"\xff\xfe", b"\xfe\xff")):
        return data.decode("utf-16"), "utf-16"

    for encoding in ("utf-8", "gb18030", "big5"):
        try:
            text = data.decode(encoding)
            # Reject decodings that produce an implausible amount of control chars.
            controls = sum(1 for char in text[:5000] if ord(char) < 9)
            if controls / max(len(text[:5000]), 1) > 0.02:
                continue
            return text, encoding
        except UnicodeDecodeError:
            continue

    best = from_bytes(data).best()
    if best is not None:
        return str(best), best.encoding or "unknown"
    return data.decode("utf-8", errors="replace"), "utf-8-replace"


class TxtParser(DocumentParser):
    format = "txt"
    extensions = (".txt",)

    def parse(self, path: Path, filename: str) -> ParsedDocument:
        try:
            data = path.read_bytes()
        except OSError as exc:
            raise DocumentParseError(f"Cannot read TXT file: {exc}") from exc
        if not data.strip():
            raise DocumentParseError("TXT file is empty")

        text, encoding = decode_bytes(data)
        text = text.replace("\r\n", "\n").replace("\r", "\n").replace("\x00", "")
        lines = text.split("\n")
        metadata = guess_metadata(filename, "\n".join(lines[:200]))
        title = metadata["title"]
        chapters = build_chapters(lines, default_title=title)
        if not chapters:
            raise DocumentParseError("No readable text found in TXT file")

        metadata["extra"]["text_encoding"] = encoding
        return ParsedDocument(
            format=self.format,
            chapters=chapters,
            metadata=metadata,
            warnings=[] if encoding not in {"utf-8-replace"} else ["Encoding fallback used"],
        )
