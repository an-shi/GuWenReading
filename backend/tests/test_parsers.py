from __future__ import annotations

from pathlib import Path

import pytest
from docx import Document
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.cidfonts import UnicodeCIDFont
from reportlab.pdfgen import canvas

from app.core.errors import AppError
from app.modules.document_parser import parse_document
from app.modules.document_parser.metadata import filename_title, guess_metadata
from app.modules.document_parser.txt_parser import decode_bytes


def test_decode_gb18030_text():
    raw = "史记卷一\n黄帝者，少典之子。".encode("gb18030")
    text, encoding = decode_bytes(raw)
    assert "黄帝者" in text
    assert encoding == "gb18030"


def test_decode_utf8_bom():
    raw = b"\xef\xbb\xbf" + "黃帝".encode("utf-8")
    text, encoding = decode_bytes(raw)
    assert text == "黃帝"
    assert encoding == "utf-8-sig"


def test_filename_title_and_metadata():
    assert "史记" in filename_title("史记（司马迁）.txt")
    metadata = guess_metadata("汉书.txt", "作者：班固\n朝代：汉\n\n高祖，沛丰邑人。")
    assert metadata["author"] == "班固"
    assert metadata["dynasty"] == "汉"


def test_txt_parser_chapters(tmp_path: Path):
    path = tmp_path / "史记.txt"
    path.write_text(
        "史记\n作者：司马迁\n\n卷一 五帝本纪\n\n黄帝者，少典之子。\n生而神灵。\n\n卷二 夏本纪\n\n禹之父曰鲧。\n",
        encoding="utf-8",
    )
    document = parse_document(path, "史记.txt")
    assert document.format == "txt"
    assert len(document.chapters) == 3
    assert "五帝本纪" in document.chapters[1].title
    assert document.chapters[1].paragraphs[0].startswith("黄帝者，少典之子。")
    assert "生而神灵" in document.chapters[1].paragraphs[0]


def test_docx_parser(tmp_path: Path):
    path = tmp_path / "doc.docx"
    document = Document()
    document.add_heading("卷一 五帝本纪", level=1)
    document.add_paragraph("黄帝者，少典之子，姓公孙，名曰轩辕。")
    document.add_heading("卷二 夏本纪", level=1)
    document.add_paragraph("禹之父曰鲧。")
    table = document.add_table(rows=1, cols=2)
    table.cell(0, 0).text = "项目"
    table.cell(0, 1).text = "内容"
    document.save(path)

    parsed = parse_document(path, "doc.docx")
    assert parsed.format == "docx"
    titles = [chapter.title for chapter in parsed.chapters]
    assert any("五帝本纪" in title for title in titles)
    all_paragraphs = [p for chapter in parsed.chapters for p in chapter.paragraphs]
    assert any("黄帝者" in p for p in all_paragraphs)
    assert any("项目\t内容" in p for p in all_paragraphs)


def test_epub_parser(tmp_path: Path):
    from ebooklib import epub

    path = tmp_path / "book.epub"
    book = epub.EpubBook()
    book.set_identifier("guwenreading-test")
    book.set_title("史记")
    book.set_language("zh")
    book.add_author("司马迁")
    chapter1 = epub.EpubHtml(title="卷一 五帝本纪", file_name="chap1.xhtml", lang="zh")
    chapter1.content = "<html><body><h1>卷一 五帝本纪</h1><p>黄帝者，少典之子。</p><p>生而神灵。</p></body></html>"
    chapter2 = epub.EpubHtml(title="卷二 夏本纪", file_name="chap2.xhtml", lang="zh")
    chapter2.content = "<html><body><h1>卷二 夏本纪</h1><p>禹之父曰鲧。</p></body></html>"
    book.add_item(chapter1)
    book.add_item(chapter2)
    book.toc = (chapter1, chapter2)
    book.add_item(epub.EpubNcx())
    book.add_item(epub.EpubNav())
    book.spine = ["nav", chapter1, chapter2]
    epub.write_epub(str(path), book)

    parsed = parse_document(path, "book.epub")
    assert parsed.format == "epub"
    assert parsed.metadata["title"] == "史记"
    assert parsed.metadata["author"] == "司马迁"
    assert len(parsed.chapters) == 2
    assert any("黄帝者" in p for p in parsed.chapters[0].paragraphs)


def test_pdf_parser_text_pdf(tmp_path: Path):
    path = tmp_path / "book.pdf"
    pdfmetrics.registerFont(UnicodeCIDFont("STSong-Light"))
    pdf = canvas.Canvas(str(path))
    pdf.setFont("STSong-Light", 13)
    pdf.drawString(60, 780, "卷一 五帝本纪")
    pdf.drawString(60, 750, "黄帝者，少典之子，姓公孙，名曰轩辕。生而神灵，弱而能言。")
    pdf.drawString(60, 720, "轩辕之时，神农氏世衰。诸侯相侵伐，暴虐百姓。")
    pdf.showPage()
    pdf.save()

    parsed = parse_document(path, "book.pdf")
    assert parsed.format == "pdf"
    assert "五帝本纪" in parsed.chapters[0].title
    text = "\n".join(p for chapter in parsed.chapters for p in chapter.paragraphs)
    assert "黄帝者" in text
    assert "神农氏" in text


def test_scanned_pdf_rejected_clearly(tmp_path: Path):
    path = tmp_path / "blank.pdf"
    pdf = canvas.Canvas(str(path))
    pdf.showPage()
    pdf.save()
    with pytest.raises(AppError) as error:
        parse_document(path, "blank.pdf")
    assert "OCR" in error.value.message
