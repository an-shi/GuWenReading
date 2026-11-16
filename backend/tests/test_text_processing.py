from __future__ import annotations

from app.modules.text_processor.converter import to_simplified, to_traditional
from app.modules.text_processor.splitter import split_sentences


def test_split_basic_classical_sentences():
    text = "黄帝者，少典之子，姓公孙，名曰轩辕。生而神灵，弱而能言。"
    spans = split_sentences(text)
    assert len(spans) == 2
    assert spans[0].text == "黄帝者，少典之子，姓公孙，名曰轩辕。"
    assert spans[1].text == "生而神灵，弱而能言。"
    assert spans[0].start == 0
    assert spans[1].start == len(spans[0].text)
    for span in spans:
        assert text[span.start:span.end] == span.text


def test_split_keeps_quotes_and_reconstructs_text():
    text = "王曰：“善。”乃下令曰：“可。”众皆从之。"
    spans = split_sentences(text)
    assert [span.text for span in spans] == ["王曰：“善。”", "乃下令曰：“可。”", "众皆从之。"]
    joined = "".join(span.text for span in spans)
    assert joined == text


def test_offsets_with_base_offset():
    text = "太甲既立。不明。"
    spans = split_sentences(text, base_offset=100)
    assert spans[0].start == 100
    assert spans[0].end == 105
    assert spans[1].start == 105


def test_long_unpunctuated_text_flagged_for_review():
    # Without any comma/terminal punctuation we preserve the paragraph and ask
    # for human review rather than inventing a risky arbitrary split.
    text = "甲" * 500
    spans = split_sentences(text)
    assert len(spans) == 1
    assert spans[0].needs_review
    assert spans[0].confidence <= 0.6
    assert spans[0].text == text


def test_no_terminal_punctuation_single_span():
    text = "黄帝者少典之子"
    spans = split_sentences(text)
    assert len(spans) == 1
    assert spans[0].text == text
    assert spans[0].confidence < 1.0


def test_ellipsis_and_closing_quote_stay_with_sentence():
    text = "其言曰：“不可……。”遂止。"
    spans = split_sentences(text)
    assert spans[0].text == "其言曰：“不可……。”"
    assert spans[1].text == "遂止。"


def test_whitespace_only_returns_empty():
    assert split_sentences("   \n\t ") == []


def test_traditional_simplified_conversion_does_not_require_original_mutation():
    original = "黃帝者，少典之子。"
    simplified = to_simplified(original)
    assert original == "黃帝者，少典之子。"
    assert "黄" in simplified
    assert to_traditional(simplified) != ""
