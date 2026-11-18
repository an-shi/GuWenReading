import 'dart:convert';
import 'dart:math' as math;

import 'lexicon.dart';

enum LocalConfidence { high, medium, low }

class LocalToken {
  const LocalToken({
    required this.word,
    required this.kind,
    required this.gloss,
    this.known = true,
    this.ambiguous = false,
    this.note,
  });
  final String word;
  final String kind;
  final String gloss;
  final bool known;
  final bool ambiguous;
  final String? note;

  Map<String, Object?> toJson() => {
    'word': word,
    'kind': kind,
    'gloss': gloss,
    'known': known,
    'ambiguous': ambiguous,
    if (note != null) 'note': note,
  };
}

class LocalCandidate {
  const LocalCandidate({
    required this.text,
    required this.score,
    required this.notes,
  });
  final String text;
  final double score;
  final List<String> notes;

  Map<String, Object?> toJson() => {
    'text': text,
    'score': score,
    'notes': notes,
  };
}

class LocalTranslationResult {
  const LocalTranslationResult({
    required this.text,
    required this.confidence,
    required this.score,
    required this.tokens,
    required this.rules,
    required this.uncertainties,
    required this.candidates,
  });

  final String text;
  final LocalConfidence confidence;
  final double score;
  final List<LocalToken> tokens;
  final List<String> rules;
  final List<String> uncertainties;
  final List<LocalCandidate> candidates;

  String get confidenceLabel => switch (confidence) {
    LocalConfidence.high => '高',
    LocalConfidence.medium => '中',
    LocalConfidence.low => '低',
  };

  Map<String, Object?> toJson() => {
    'text': text,
    'confidence': confidence.name,
    'score': score,
    'tokens': tokens.map((token) => token.toJson()).toList(),
    'rules': rules,
    'uncertainties': uncertainties,
    'candidates': candidates.map((candidate) => candidate.toJson()).toList(),
    'engine': 'local_rule',
    'lexicon_version': lexiconVersion,
  };

  static LocalTranslationResult fromJson(Map<String, dynamic> json) {
    final tokens = (json['tokens'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => LocalToken(
            word: '${item['word'] ?? ''}',
            kind: '${item['kind'] ?? ''}',
            gloss: '${item['gloss'] ?? ''}',
            known: item['known'] != false,
            ambiguous: item['ambiguous'] == true,
            note: item['note'] as String?,
          ),
        )
        .toList();
    final candidates = (json['candidates'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => LocalCandidate(
            text: '${item['text'] ?? ''}',
            score: (item['score'] as num? ?? 0).toDouble(),
            notes: (item['notes'] as List? ?? const [])
                .map((value) => '$value')
                .toList(),
          ),
        )
        .toList();
    return LocalTranslationResult(
      text: '${json['text'] ?? ''}',
      confidence: LocalConfidence.values.firstWhere(
        (value) => value.name == json['confidence'],
        orElse: () => LocalConfidence.low,
      ),
      score: (json['score'] as num? ?? 0).toDouble(),
      tokens: tokens,
      rules: (json['rules'] as List? ?? const [])
          .map((value) => '$value')
          .toList(),
      uncertainties: (json['uncertainties'] as List? ?? const [])
          .map((value) => '$value')
          .toList(),
      candidates: candidates,
    );
  }
}

class LocalClassicalEngine {
  const LocalClassicalEngine();

  static const engineVersion = 'local-engine-1';

  LocalTranslationResult translate(
    String source, {
    String? previousSentence,
    String? nextSentence,
  }) {
    final tokens = _tokenize(source);
    final rules = <String>[];
    final uncertainties = <String>[];
    final pattern = _matchPattern(source, rules);
    var text = pattern ?? _compose(tokens, previousSentence, uncertainties);
    text = _applyJudgment(source, text, rules);
    text = _applyEllipsis(tokens, text, uncertainties);
    final known = tokens.where((token) => token.known).length;
    final unknown = tokens.length - known;
    final ambiguous = tokens.where((token) => token.ambiguous).length;
    var score = tokens.isEmpty
        ? 0.0
        : known / tokens.length * 0.65 +
              (1 - math.min(unknown, 5) / 5) * 0.15 +
              (pattern == null ? 0 : 0.15) -
              math.min(ambiguous, 4) * 0.04 -
              (text.contains('（推测') ? 0.04 : 0);
    score = score.clamp(0.0, 0.98);
    final confidence = score >= 0.78
        ? LocalConfidence.high
        : score >= 0.52
        ? LocalConfidence.medium
        : LocalConfidence.low;
    final candidates = <LocalCandidate>[
      LocalCandidate(text: text, score: score, notes: rules),
    ];
    if (ambiguous > 0) {
      final alternate = _compose(tokens, previousSentence, [], alternate: true);
      candidates.add(
        LocalCandidate(
          text: alternate,
          score: (score - 0.12).clamp(0.0, 0.95),
          notes: ['多义词取次选释义', ...rules],
        ),
      );
    }
    return LocalTranslationResult(
      text: text,
      confidence: confidence,
      score: score,
      tokens: tokens,
      rules: rules,
      uncertainties: uncertainties,
      candidates: candidates,
    );
  }

  List<LocalToken> _tokenize(String source) {
    final tokens = <LocalToken>[];
    var index = 0;
    const punctuation = '，。；：！？、,.!?;:';
    while (index < source.length) {
      final char = source[index];
      if (punctuation.contains(char)) {
        tokens.add(
          LocalToken(word: char, kind: '标点', gloss: char, note: '保留标点'),
        );
        index += 1;
        continue;
      }
      var matched = false;
      for (
        var length = math.min(4, source.length - index);
        length >= 1;
        length--
      ) {
        final word = source.substring(index, index + length);
        final entry = lookupLexicon(word);
        if (entry != null) {
          final meanings = entry.meanings;
          tokens.add(
            LocalToken(
              word: word,
              kind: entry.kind,
              gloss: meanings.first.modern,
              ambiguous: meanings.length > 1,
              note: meanings.length > 1
                  ? '候选：${meanings.map((m) => m.modern).join(' / ')}'
                  : null,
            ),
          );
          index += length;
          matched = true;
          break;
        }
      }
      if (!matched) {
        tokens.add(
          LocalToken(
            word: char,
            kind: '未知',
            gloss: char,
            known: false,
            note: '词库未收录，保留原字',
          ),
        );
        index += 1;
      }
    }
    return tokens;
  }

  String? _matchPattern(String source, List<String> rules) {
    final patterns = <(RegExp, String Function(RegExpMatch), String)>[
      (
        RegExp(r'^(.+?)者[，,]?(.+)也[。！？]?$'),
        (match) => '${match[1]}是${match[2]}',
        '判断句：……者，……也',
      ),
      (RegExp(r'不亦(.+?)乎[？?]?$'), (match) => '不也是${match[1]}吗', '固定句式：不亦……乎'),
      (RegExp(r'何以(.+?)[？?]?$'), (match) => '凭什么${match[1]}', '固定句式：何以……'),
      (RegExp(r'何(.+?)之有[？?]?$'), (match) => '有什么${match[1]}呢', '宾语前置：何……之有'),
      (
        RegExp(r'为(.+?)所(.+?)[。！？]?$'),
        (match) => '${match[2]}被${match[1]}',
        '被动句：为……所……',
      ),
      (
        RegExp(r'见(.+?)于(.+?)[。！？]?$'),
        (match) => '${match[1]}被${match[2]}',
        '被动句：见……于……',
      ),
      (
        RegExp(r'以(.+?)为(.+?)[。！？]?$'),
        (match) => '把${match[1]}当作${match[2]}',
        '固定句式：以……为……',
      ),
    ];
    for (final entry in patterns) {
      final match = entry.$1.firstMatch(source.trim());
      if (match != null) {
        rules.add(entry.$3);
        return entry.$2(match);
      }
    }
    return null;
  }

  String _compose(
    List<LocalToken> tokens,
    String? previousSentence,
    List<String> uncertainties, {
    bool alternate = false,
  }) {
    final buffer = StringBuffer();
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      final previous = i > 0 ? tokens[i - 1] : null;
      final next = i + 1 < tokens.length ? tokens[i + 1] : null;
      var gloss = token.gloss;
      if (token.ambiguous && alternate) {
        final entry = lookupLexicon(token.word);
        if (entry != null && entry.meanings.length > 1) {
          gloss = entry.meanings[1].modern;
        }
      }
      if (token.word == '之') {
        if (previous == null) {
          gloss = '这';
        } else if (next != null && next.kind == '实词') {
          gloss = '的';
          if (previous.kind == '虚词') gloss = '它';
        } else {
          gloss = '它';
        }
      } else if (token.word == '而') {
        gloss = next != null && (next.word == '不' || next.word == '未')
            ? '却'
            : '并且';
      } else if (token.word == '其') {
        gloss = next != null && next.kind == '实词' ? '他的' : '大概';
      } else if (token.word == '以') {
        gloss = next != null && next.kind == '实词' ? '用' : '来';
      } else if (token.word == '于') {
        gloss = '在';
      } else if (token.word == '为') {
        gloss = '是';
      } else if (token.word == '也') {
        gloss = '';
      } else if (token.word == '者') {
        gloss = '的人';
      } else if (token.word == '矣') {
        gloss = '了';
      } else if (token.word == '乎') {
        gloss = '吗';
      } else if (token.word == '哉') {
        gloss = '呢';
      }
      if (!token.known) {
        uncertainties.add('“${token.word}”未收录，按原字保留');
      }
      buffer.write(gloss);
    }
    var text = buffer.toString();
    text = text
        .replaceAll('，', '，')
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('。。', '。')
        .replaceAll('，。', '。');
    if (previousSentence != null && text.startsWith('之')) {
      uncertainties.add('句首代词指代依赖上文，未能自动补全');
    }
    if (!text.endsWith('。') && !text.endsWith('！') && !text.endsWith('？')) {
      text = '$text。';
    }
    return text;
  }

  String _applyJudgment(String source, String text, List<String> rules) {
    if (source.contains('乃') || source.contains('即') || source.contains('则')) {
      rules.add('判断结构：乃/即/则');
      if (!text.contains('是')) return '${text.replaceAll('。', '')}（判断）';
    }
    return text;
  }

  String _applyEllipsis(
    List<LocalToken> tokens,
    String text,
    List<String> uncertainties,
  ) {
    final hasSubject = tokens.isNotEmpty && tokens.first.kind == '实词';
    if (!hasSubject) {
      uncertainties.add('原文缺少明确主语，未自动补全');
      return '（推测主语）$text';
    }
    return text;
  }
}

String localResultJson(LocalTranslationResult result) =>
    jsonEncode(result.toJson());
