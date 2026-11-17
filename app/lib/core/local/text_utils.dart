import 'dart:math' as math;

class SentenceSpan {
  const SentenceSpan({
    required this.text,
    required this.start,
    required this.end,
    required this.needsReview,
    required this.confidence,
  });

  final String text;
  final int start;
  final int end;
  final bool needsReview;
  final double confidence;
}

class ChapterBlock {
  const ChapterBlock({required this.title, required this.paragraphs});
  final String title;
  final List<String> paragraphs;
}

class DocumentParseException implements Exception {
  DocumentParseException(this.message);
  final String message;
  @override
  String toString() => message;
}

const _terminals = {'。', '！', '？', '；', '!', '?', ';', '…'};
const _trailing = {
  ..._terminals,
  '”',
  '’',
  '」',
  '』',
  '）',
  ')',
  '】',
  '》',
  '〉',
  '"',
  "'",
};
const _openQuotes = {'“', '‘', '「', '『', '（', '(', '【', '《', '〈'};
const _closeQuotes = {'”', '’', '」', '』', '）', ')', '】', '》', '〉'};
const _commaBreaks = {'，', '、', '：', ',', ':'};

bool _isDotTerminal(String text, int index) {
  if (text[index] != '.') return false;
  final before = index > 0 ? text[index - 1] : '';
  final after = index + 1 < text.length ? text[index + 1] : '';
  return !RegExp(r'\d').hasMatch(before) &&
      (after.isEmpty || RegExp(r'\s').hasMatch(after));
}

List<(int, int)> _longClauseSplit(String text, int start, int end) {
  if (end - start <= 320) return [(start, end)];
  final middle = start + (end - start) ~/ 2;
  final candidates = <int>[];
  for (
    var index = start + 80;
    index < end - 20 && index < text.length;
    index++
  ) {
    if (_commaBreaks.contains(text[index])) candidates.add(index);
  }
  if (candidates.isEmpty) return [(start, end)];
  candidates.sort((a, b) => (a - middle).abs().compareTo((b - middle).abs()));
  final chosen = candidates.first;
  return [
    ..._longClauseSplit(text, start, chosen + 1),
    ..._longClauseSplit(text, chosen + 1, end),
  ];
}

List<SentenceSpan> splitSentences(String text, {int baseOffset = 0}) {
  if (text.trim().isEmpty) return const [];
  final length = text.length;
  final boundary = <(int, int, double)>[];
  var segmentStart = 0;
  var index = 0;
  while (index < length) {
    final char = text[index];
    if (!(_terminals.contains(char) || _isDotTerminal(text, index))) {
      index += 1;
      continue;
    }
    var end = index + 1;
    while (end < length &&
        (_trailing.contains(text[end]) ||
            text[end] == ' ' ||
            text[end] == '\t' ||
            text[end] == '　')) {
      end += 1;
    }
    boundary.add((segmentStart, end, 1.0));
    segmentStart = end;
    index = end;
  }
  if (segmentStart < length) {
    final remaining = length - segmentStart;
    boundary.add((segmentStart, length, remaining < 24 ? 0.8 : 0.55));
  }

  final spans = <(int, int, double)>[];
  for (final (left, right, confidence) in boundary) {
    for (final (partLeft, partRight) in _longClauseSplit(text, left, right)) {
      final segment = text.substring(partLeft, partRight);
      if (segment.trim().isEmpty) continue;
      var value = confidence;
      if (segment.trim().length > 320 || partRight - partLeft != right - left) {
        value = math.min(value, 0.6);
      }
      spans.add((partLeft, partRight, value));
    }
  }

  final normalised = <(int, int, double)>[];
  for (var (left, right, confidence) in spans) {
    while (left < right && _isSpace(text[left])) {
      left += 1;
    }
    while (right > left && _isSpace(text[right - 1])) {
      right -= 1;
    }
    if (left >= right) continue;
    final content = text.substring(left, right);
    final punctuationOnly = content.runes.every((rune) {
      final char = String.fromCharCode(rune);
      return char.trim().isEmpty ||
          _terminals.contains(char) ||
          _closeQuotes.contains(char);
    });
    if (normalised.isNotEmpty &&
        (content.runes.length <= 1 ||
            punctuationOnly ||
            _closeQuotes.contains(content[0]))) {
      final (prevLeft, _, prevConfidence) = normalised.removeLast();
      normalised.add((prevLeft, right, math.min(prevConfidence, confidence)));
      continue;
    }
    normalised.add((left, right, confidence));
  }

  if (normalised.isEmpty && text.trim().isNotEmpty) {
    final left = text.length - text.trimLeft().length;
    final right = text.trimRight().length;
    normalised.add((left, right, 0.5));
  }

  final quoteBalance =
      text.runes
          .where((r) => _openQuotes.contains(String.fromCharCode(r)))
          .length -
      text.runes
          .where((r) => _closeQuotes.contains(String.fromCharCode(r)))
          .length;
  final unbalanced = quoteBalance != 0;
  return [
    for (final (left, right, confidence) in normalised)
      SentenceSpan(
        text: text.substring(left, right),
        start: baseOffset + left,
        end: baseOffset + right,
        needsReview:
            (unbalanced ? math.min(confidence, 0.7) : confidence) < 0.75,
        confidence: (unbalanced ? math.min(confidence, 0.7) : confidence),
      ),
  ];
}

bool _isSpace(String char) =>
    char == ' ' || char == '\t' || char == '\n' || char == '\r' || char == '　';

final List<RegExp> _chapterPatterns = [
  RegExp(r'^第[〇零一二三四五六七八九十百千万两0-9０-９]+[卷回章节篇部集](?:\s|$|[：:、.．·]|.{0,24}$)'),
  RegExp(r'^卷[〇零一二三四五六七八九十百千0-9]+(?:\s|$|[：:、.．]|.{0,20}$)'),
  RegExp(r'^[上下中]卷(?:\s|$)'),
  RegExp(r'^[序跋志表传纪世家列传本纪书志]{1,4}[一二三四五六七八九十]*$'),
  RegExp(r'^(?:序言|前言|自序|后序|后记|附录|凡例|目录|楔子|引子|尾声)$'),
  RegExp(r'^#{1,3}\s+\S+'),
  RegExp(r'^(?:第\s*)?[0-9]{1,4}[、.．]\s*\S{2,30}$'),
];

bool isChapterHeading(String line) {
  final value = line.trim().replaceFirst('\ufeff', '');
  if (value.isEmpty || value.length > 42) return false;
  if (value.endsWith('。') ||
      value.endsWith('，') ||
      value.endsWith('！') ||
      value.endsWith('？') ||
      value.endsWith('；')) {
    return false;
  }
  if ((value.startsWith('　') || value.startsWith('  ')) && value.length > 16) {
    return false;
  }
  return _chapterPatterns.any((pattern) => pattern.hasMatch(value));
}

List<(String, List<String>)> splitLinesIntoChapters(
  List<String> lines, {
  required String defaultTitle,
  String? sourceTitle,
}) {
  final headings = <int>[];
  for (var i = 0; i < lines.length; i++) {
    if (isChapterHeading(lines[i])) headings.add(i);
  }
  if (headings.isEmpty) return [(defaultTitle, lines)];

  final chapters = <(String, List<String>)>[];
  if (headings.first > 0) {
    final preface = lines.sublist(0, headings.first);
    if (preface.any((line) => line.trim().isNotEmpty)) {
      chapters.add(('${sourceTitle ?? defaultTitle}·卷首', preface));
    }
  }
  for (var position = 0; position < headings.length; position++) {
    final start = headings[position];
    final end = position + 1 < headings.length
        ? headings[position + 1]
        : lines.length;
    final title = lines[start].trim().replaceFirst(RegExp(r'^#+'), '').trim();
    chapters.add((
      title.isEmpty
          ? defaultTitle
          : title.substring(0, math.min(title.length, 400)),
      lines.sublist(start + 1, end),
    ));
  }
  return chapters;
}

String _joinWrapped(String left, String right) {
  if (left.isEmpty) return right;
  final leftChar = left[left.length - 1];
  final rightChar = right[0];
  final cjk = RegExp(r'[\u3400-\u9fff，。！？；：“”‘’、（）《》]');
  if (cjk.hasMatch(leftChar) || cjk.hasMatch(rightChar)) return '$left$right';
  return '$left $right';
}

List<String> linesToParagraphs(List<String> lines) {
  final hasBlankLines = lines.any((line) => line.trim().isEmpty);
  if (!hasBlankLines) {
    return [
      for (final line in lines)
        if (line.trim().isNotEmpty) line.trim(),
    ];
  }
  final paragraphs = <String>[];
  var buffer = '';
  for (final line in lines) {
    final value = line.trim();
    if (value.isEmpty) {
      if (buffer.isNotEmpty) {
        paragraphs.add(buffer);
        buffer = '';
      }
      continue;
    }
    buffer = _joinWrapped(buffer, value);
  }
  if (buffer.isNotEmpty) paragraphs.add(buffer);
  return cleanParagraphs(paragraphs);
}

List<ChapterBlock> buildChapters(
  List<String> lines, {
  required String defaultTitle,
}) {
  final raw = splitLinesIntoChapters(lines, defaultTitle: defaultTitle);
  final chapters = <ChapterBlock>[];
  final pendingTitles = <String>[];
  for (final (title, body) in raw) {
    final paragraphs = cleanParagraphs(linesToParagraphs(body));
    if (paragraphs.isEmpty) {
      pendingTitles.add(title);
      continue;
    }
    var fullTitle = title;
    if (pendingTitles.isNotEmpty) {
      fullTitle = [...pendingTitles, title].join(' · ');
      pendingTitles.clear();
    }
    chapters.add(
      ChapterBlock(
        title: fullTitle.substring(0, math.min(fullTitle.length, 400)),
        paragraphs: paragraphs,
      ),
    );
  }
  if (pendingTitles.isNotEmpty) {
    if (chapters.isNotEmpty) {
      final last = chapters.removeLast();
      chapters.add(
        ChapterBlock(
          title: '${pendingTitles.join(' · ')} · ${last.title}'.substring(
            0,
            math.min(
              400,
              '${pendingTitles.join(' · ')} · ${last.title}'.length,
            ),
          ),
          paragraphs: last.paragraphs,
        ),
      );
    } else if (lines.isNotEmpty) {
      final paragraphs = linesToParagraphs(lines);
      if (paragraphs.isNotEmpty) {
        chapters.add(
          ChapterBlock(
            title: pendingTitles.join(' · '),
            paragraphs: cleanParagraphs(paragraphs),
          ),
        );
      }
    }
  }
  if (chapters.isEmpty && lines.isNotEmpty) {
    final paragraphs = cleanParagraphs(linesToParagraphs(lines));
    if (paragraphs.isNotEmpty) {
      chapters.add(ChapterBlock(title: defaultTitle, paragraphs: paragraphs));
    }
  }
  return chapters;
}

List<String> cleanParagraphs(List<String> paragraphs) {
  final cleaned = <String>[];
  for (final paragraph in paragraphs) {
    final value = paragraph
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\x00', '')
        .trim();
    if (value.isNotEmpty) cleaned.add(value);
  }
  return cleaned;
}

String filenameTitle(String filename) {
  var stem = filename.split(RegExp(r'[/\\]')).last;
  final dot = stem.lastIndexOf('.');
  if (dot > 0) stem = stem.substring(0, dot);
  stem = stem.replaceAll(RegExp(r'[_\s]+'), ' ').trim();
  stem = stem.replaceFirst(RegExp(r'\s*[-—]\s*.*$'), '').trim();
  final titleMatch = RegExp(r'《([^》]{1,60})》').firstMatch(stem);
  if (titleMatch != null) stem = titleMatch.group(1)!;
  return stem.isEmpty ? '未命名古籍' : stem.substring(0, math.min(stem.length, 200));
}

({String title, String? author, String? dynasty}) guessMetadata(
  String filename,
  String sample,
) {
  var title = filenameTitle(filename);
  String? author;
  String? dynasty;
  final lines = [
    for (final line in sample.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ].take(12).toList();
  for (final line in lines) {
    author ??= RegExp(r'(?:作者|著者|撰者|撰)\s*[：:]\s*(.{1,40})')
        .firstMatch(line)
        ?.group(1)
        ?.trim()
        .replaceAll(RegExp(r'[，,。]$'), '');
    dynasty ??= RegExp(r'(?:朝代|时代|朝)\s*[：:]\s*(.{1,30})')
        .firstMatch(line)
        ?.group(1)
        ?.trim()
        .replaceAll(RegExp(r'[，,。]$'), '');
  }
  for (final line in lines.take(4)) {
    final match = RegExp(r'《([^》]{1,60})》').firstMatch(line);
    if (match != null && !RegExp(r'[，。！？；]').hasMatch(line)) {
      title = match.group(1)!.trim();
      break;
    }
  }
  author ??= RegExp(r'[（(]([^）)]{2,20})[）)]\s*$')
      .firstMatch(filenameTitle(filename))
      ?.group(1);
  return (title: title, author: author, dynasty: dynasty);
}
