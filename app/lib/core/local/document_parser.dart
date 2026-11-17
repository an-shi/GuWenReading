import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:charset_converter/charset_converter.dart';
import 'package:collection/collection.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';

import 'text_utils.dart';

class ParsedDocument {
  const ParsedDocument({
    required this.format,
    required this.chapters,
    required this.metadata,
    this.cover,
    this.warnings = const [],
  });

  final String format;
  final List<ChapterBlock> chapters;
  final ParsedMetadata metadata;
  final Uint8List? cover;
  final List<String> warnings;
}

class ParsedMetadata {
  const ParsedMetadata({
    required this.title,
    this.author,
    this.dynasty,
    this.description,
  });

  final String title;
  final String? author;
  final String? dynasty;
  final String? description;
}

typedef ParseProgressCallback = void Function(double progress, String message);

Future<ParsedDocument> parseDocument({
  required String filename,
  required Uint8List bytes,
  ParseProgressCallback? onProgress,
}) async {
  final extension = p.extension(filename).toLowerCase();
  onProgress?.call(0.01, '正在检查文件类型');
  switch (extension) {
    case '.txt':
      return _parseTxt(filename, bytes, onProgress);
    case '.epub':
      return _parseEpub(filename, bytes, onProgress);
    case '.docx':
      return _parseDocx(filename, bytes, onProgress);
    case '.pdf':
      return _parsePdf(filename, bytes, onProgress);
    default:
      throw DocumentParseException('不支持的文件格式：$extension');
  }
}

Future<ParsedDocument> _parseTxt(
  String filename,
  Uint8List bytes,
  ParseProgressCallback? onProgress,
) async {
  if (bytes.isEmpty) throw DocumentParseException('TXT 文件为空');
  onProgress?.call(0.05, '正在识别文本编码');
  final decoded = await _decodeText(bytes);
  final text = decoded.text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\x00', '');
  onProgress?.call(0.18, '正在识别章节结构');
  final lines = text.split('\n');
  final meta = guessMetadata(filename, lines.take(200).join('\n'));
  final chapters = buildChapters(lines, defaultTitle: meta.title);
  if (chapters.isEmpty) throw DocumentParseException('TXT 中没有可读文本');
  onProgress?.call(0.31, '已识别 ${chapters.length} 个章节');
  return ParsedDocument(
    format: 'txt',
    chapters: chapters,
    metadata: ParsedMetadata(
      title: meta.title,
      author: meta.author,
      dynasty: meta.dynasty,
    ),
    warnings: decoded.warning == null ? const [] : [decoded.warning!],
  );
}

class _DecodedText {
  const _DecodedText(this.text, this.encoding, [this.warning]);
  final String text;
  final String encoding;
  final String? warning;
}

Future<_DecodedText> _decodeText(Uint8List bytes) async {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return _DecodedText(
      utf8.decode(bytes.sublist(3), allowMalformed: true),
      'utf-8-sig',
    );
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _DecodedText(
      _decodeUtf16(bytes.sublist(2), littleEndian: true),
      'utf-16le',
    );
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _DecodedText(
      _decodeUtf16(bytes.sublist(2), littleEndian: false),
      'utf-16be',
    );
  }
  try {
    return _DecodedText(utf8.decode(bytes), 'utf-8');
  } on FormatException {
    // Try common Chinese encodings through the platform converter.
  }
  for (final encoding in const ['gb18030', 'gbk', 'big5']) {
    try {
      final text = await CharsetConverter.decode(encoding, bytes);
      if (!text.contains('\uFFFD')) {
        return _DecodedText(text, encoding);
      }
    } catch (_) {
      // Try the next encoding.
    }
  }
  return _DecodedText(
    utf8.decode(bytes, allowMalformed: true),
    'utf-8-replace',
    '编码识别失败，已使用 UTF-8 容错解码；请检查原文是否完整。',
  );
}

String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add(
      littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1],
    );
  }
  return String.fromCharCodes(units);
}

Future<ParsedDocument> _parseEpub(
  String filename,
  Uint8List bytes,
  ParseProgressCallback? onProgress,
) async {
  onProgress?.call(0.03, '正在解压 EPUB');
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes, verify: false);
  } catch (error) {
    throw DocumentParseException('EPUB 压缩包无法读取：$error');
  }
  onProgress?.call(0.08, '正在读取 EPUB 目录');
  final files = {for (final file in archive.files) file.name: file};
  final containerFile = files['META-INF/container.xml'];
  if (containerFile == null) {
    throw DocumentParseException('EPUB 缺少 META-INF/container.xml');
  }
  final XmlDocument containerXml;
  try {
    containerXml = XmlDocument.parse(
      utf8.decode(containerFile.content as List<int>),
    );
  } catch (error) {
    throw DocumentParseException('EPUB 的 container.xml 无法解析：$error');
  }
  final rootfile = _firstByLocalName(containerXml, 'rootfile');
  final opfPath = rootfile?.getAttribute('full-path');
  if (opfPath == null || !files.containsKey(opfPath)) {
    throw DocumentParseException('EPUB 找不到 OPF 清单');
  }
  final XmlDocument opfXml;
  try {
    opfXml = XmlDocument.parse(
      utf8.decode(files[opfPath]!.content as List<int>),
    );
  } catch (error) {
    throw DocumentParseException('EPUB 的 OPF 清单无法解析：$error');
  }
  onProgress?.call(0.11, '正在读取书籍信息与章节清单');
  final opfDir = p.dirname(opfPath);
  final title = _firstTextByLocalName(opfXml, 'title');
  final creator = _firstTextByLocalName(opfXml, 'creator');
  final language = _firstTextByLocalName(opfXml, 'language');

  final manifest = <String, XmlElement>{};
  for (final item in _elementsByLocalName(opfXml, 'item')) {
    final id = item.getAttribute('id');
    if (id != null) manifest[id] = item;
  }
  final spineIds = [
    for (final itemref in _elementsByLocalName(opfXml, 'itemref'))
      if (itemref.getAttribute('idref') != null) itemref.getAttribute('idref')!,
  ];

  final chapters = <ChapterBlock>[];
  Uint8List? cover;
  for (final item in manifest.values) {
    final properties = item.getAttribute('properties') ?? '';
    if (properties.contains('cover-image')) {
      final file =
          files[_resolveZipPath(opfDir, item.getAttribute('href') ?? '')];
      if (file != null) cover = Uint8List.fromList(file.content as List<int>);
    }
  }

  final spineStep = (spineIds.length / 40).ceil().clamp(1, 1000);
  for (var index = 0; index < spineIds.length; index++) {
    final id = spineIds[index];
    if (index % spineStep == 0 || index == spineIds.length - 1) {
      final chapterProgress = 0.12 + 0.17 * ((index + 1) / spineIds.length);
      onProgress?.call(
        chapterProgress,
        '正在解析章节文件 ${index + 1}/${spineIds.length}',
      );
    }
    final item = manifest[id];
    if (item == null) continue;
    final mediaType = item.getAttribute('media-type') ?? '';
    if (!mediaType.contains('html') && !mediaType.contains('xml')) continue;
    final href = item.getAttribute('href') ?? '';
    final file = files[_resolveZipPath(opfDir, href)];
    if (file == null) continue;
    final html = utf8.decode(file.content as List<int>, allowMalformed: true);
    final document = html_parser.parse(html);
    final body = document.body;
    if (body == null) continue;
    final headings = <String>[];
    for (final element in body.querySelectorAll('h1,h2,h3,h4,h5,h6')) {
      final value = element.text.trim();
      if (value.isNotEmpty) headings.add(value);
    }
    final lines = <String>[];
    for (final element in body.querySelectorAll(
      'h1,h2,h3,h4,h5,h6,p,blockquote,li,pre,td',
    )) {
      final value = element.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (value.isNotEmpty) lines.add(value);
    }
    final paragraphs = cleanParagraphs(lines.isEmpty ? [body.text] : lines);
    if (paragraphs.isEmpty) continue;
    final chapterTitle = headings.isNotEmpty
        ? headings.first
        : (document.querySelector('title')?.text.trim().isNotEmpty == true
              ? document.querySelector('title')!.text.trim()
              : '第 ${chapters.length + 1} 章');
    chapters.add(ChapterBlock(title: chapterTitle, paragraphs: paragraphs));
  }

  if (chapters.isEmpty) throw DocumentParseException('EPUB 中没有可读文本');
  onProgress?.call(0.31, '已解析 ${chapters.length} 个章节');
  final guessed = guessMetadata(filename, title ?? '');
  return ParsedDocument(
    format: 'epub',
    chapters: chapters,
    metadata: ParsedMetadata(
      title: (title == null || title.trim().isEmpty)
          ? guessed.title
          : title.trim(),
      author: creator,
      dynasty: _dynastyFromLanguage(language),
    ),
    cover: cover,
  );
}

String? _dynastyFromLanguage(String? language) {
  if (language == null) return null;
  final value = language.trim().toLowerCase();
  if (value.contains('zh') || value.contains('chi')) return null;
  return null;
}

String _resolveZipPath(String directory, String href) {
  final normalized = p.normalize(p.join(directory, href));
  return normalized.replaceAll('\\', '/');
}

XmlElement? _firstByLocalName(XmlNode node, String name) {
  for (final element in _elementsByLocalName(node, name)) {
    return element;
  }
  return null;
}

String? _firstTextByLocalName(XmlNode node, String name) {
  final element = _firstByLocalName(node, name);
  final text = element?.innerText.trim();
  return text == null || text.isEmpty ? null : text;
}

Iterable<XmlElement> _elementsByLocalName(XmlNode node, String name) sync* {
  if (node is XmlElement && node.localName == name) yield node;
  for (final child in node.children) {
    yield* _elementsByLocalName(child, name);
  }
}

Future<ParsedDocument> _parseDocx(
  String filename,
  Uint8List bytes,
  ParseProgressCallback? onProgress,
) async {
  onProgress?.call(0.04, '正在解压 DOCX');
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes, verify: false);
  } catch (error) {
    throw DocumentParseException('DOCX 压缩包无法读取：$error');
  }
  onProgress?.call(0.12, '正在读取 DOCX 正文');
  final documentFile = archive.files.firstWhere(
    (file) => file.name == 'word/document.xml',
    orElse: () => throw DocumentParseException('DOCX 缺少 word/document.xml'),
  );
  final documentXml = XmlDocument.parse(
    utf8.decode(documentFile.content as List<int>),
  );
  final lines = <String>[];
  for (final paragraph in _elementsByLocalName(documentXml, 'p')) {
    final texts = <String>[];
    for (final text in _elementsByLocalName(paragraph, 't')) {
      texts.add(text.innerText);
    }
    final value = texts.join().trim();
    if (value.isEmpty) continue;
    final style =
        _firstByLocalName(paragraph, 'pStyle')?.getAttribute('w:val') ??
        _firstByLocalName(paragraph, 'pStyle')?.getAttribute('val') ??
        '';
    if (style.toLowerCase().contains('heading') || style.contains('标题')) {
      lines.add('# $value');
    } else {
      lines.add(value);
    }
  }
  if (lines.isEmpty) throw DocumentParseException('DOCX 中没有可读文本');
  onProgress?.call(0.24, '正在识别章节结构');
  String? title;
  String? creator;
  final core = archive.files
      .where((file) => file.name == 'docProps/core.xml')
      .firstOrNull;
  if (core != null) {
    final xml = XmlDocument.parse(utf8.decode(core.content as List<int>));
    title = _firstTextByLocalName(xml, 'title');
    creator = _firstTextByLocalName(xml, 'creator');
  }
  final guessed = guessMetadata(filename, lines.take(100).join('\n'));
  final chapters = buildChapters(lines, defaultTitle: title ?? guessed.title);
  if (chapters.isEmpty) throw DocumentParseException('DOCX 中没有可读文本');
  onProgress?.call(0.31, '已识别 ${chapters.length} 个章节');
  return ParsedDocument(
    format: 'docx',
    chapters: chapters,
    metadata: ParsedMetadata(
      title: (title == null || title.trim().isEmpty)
          ? guessed.title
          : title.trim(),
      author: creator ?? guessed.author,
      dynasty: guessed.dynasty,
    ),
  );
}

Future<ParsedDocument> _parsePdf(
  String filename,
  Uint8List bytes,
  ParseProgressCallback? onProgress,
) async {
  onProgress?.call(0.03, '正在打开 PDF');
  PdfDocument? document;
  try {
    document = await PdfDocument.openData(bytes, sourceName: filename);
    final pages = document.pages;
    final textPages = <String>[];
    final pageStep = (pages.length / 40).ceil().clamp(1, 1000);
    for (var index = 0; index < pages.length; index++) {
      if (index % pageStep == 0 || index == pages.length - 1) {
        final pageProgress = 0.08 + 0.18 * ((index + 1) / pages.length);
        onProgress?.call(
          pageProgress,
          '正在提取第 ${index + 1}/${pages.length} 页文字',
        );
      }
      final raw = await pages[index].loadText();
      textPages.add(raw?.fullText ?? '');
    }
    onProgress?.call(0.28, '正在识别章节结构');
    final text = textPages.join('\n\n').trim();
    if (text.length < 20) {
      throw DocumentParseException('PDF 中没有可提取的文字，扫描版 PDF 需要 OCR，本版本不提供。');
    }
    final lines = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final meta = guessMetadata(filename, lines.take(200).join('\n'));
    final chapters = buildChapters(lines, defaultTitle: meta.title);
    if (chapters.isEmpty) throw DocumentParseException('PDF 中没有可读文本');
    onProgress?.call(0.31, '已识别 ${chapters.length} 个章节');
    return ParsedDocument(
      format: 'pdf',
      chapters: chapters,
      metadata: ParsedMetadata(
        title: meta.title,
        author: meta.author,
        dynasty: meta.dynasty,
      ),
    );
  } catch (error) {
    if (error is DocumentParseException) rethrow;
    throw DocumentParseException('PDF 解析失败：$error');
  } finally {
    await document?.dispose();
  }
}
