enum QualityLevel { passed, warning, failed, needsReview }

extension QualityLevelX on QualityLevel {
  String get wireValue => switch (this) {
    QualityLevel.passed => 'passed',
    QualityLevel.warning => 'warning',
    QualityLevel.failed => 'failed',
    QualityLevel.needsReview => 'needs_review',
  };

  String get label => switch (this) {
    QualityLevel.passed => '通过',
    QualityLevel.warning => '警告',
    QualityLevel.failed => '失败',
    QualityLevel.needsReview => '待审核',
  };
}

class QualityIssue {
  const QualityIssue({
    required this.code,
    required this.message,
    required this.level,
    this.reference,
  });

  final String code;
  final String message;
  final QualityLevel level;
  final String? reference;

  Map<String, Object?> toJson() => {
    'code': code,
    'message': message,
    'level': level.wireValue,
    if (reference != null) 'reference': reference,
  };
}

class QualityReport {
  const QualityReport({required this.level, required this.issues});

  final QualityLevel level;
  final List<QualityIssue> issues;

  int get failedCount =>
      issues.where((issue) => issue.level == QualityLevel.failed).length;
  int get warningCount =>
      issues.where((issue) => issue.level == QualityLevel.warning).length;
  int get reviewCount =>
      issues.where((issue) => issue.level == QualityLevel.needsReview).length;

  Map<String, Object?> toJson() => {
    'level': level.wireValue,
    'issues': issues.map((issue) => issue.toJson()).toList(),
  };
}

/// Local, deterministic output checks. No additional AI request is made.
class QualityService {
  const QualityService();

  QualityReport checkTranslations({
    required Map<int, String> translations,
    required Map<int, String> originals,
  }) {
    final issues = <QualityIssue>[];
    for (final entry in originals.entries) {
      final text = translations[entry.key];
      if (text == null) {
        issues.add(
          QualityIssue(
            code: 'missing_translation',
            message: '第 ${entry.key} 句缺少译文',
            level: QualityLevel.failed,
            reference: '${entry.key}',
          ),
        );
        continue;
      }
      if (text.trim().isEmpty) {
        issues.add(
          QualityIssue(
            code: 'empty_translation',
            message: '第 ${entry.key} 句译文为空',
            level: QualityLevel.failed,
            reference: '${entry.key}',
          ),
        );
        continue;
      }
      final source = entry.value.trim();
      if (text.trim() == source) {
        issues.add(
          QualityIssue(
            code: 'untranslated',
            message: '第 ${entry.key} 句与原文相同，可能未翻译',
            level: QualityLevel.warning,
            reference: '${entry.key}',
          ),
        );
      }
      final ratio = text.length / source.length.clamp(1, 1 << 30);
      if (ratio > 4.5) {
        issues.add(
          QualityIssue(
            code: 'overlong',
            message: '第 ${entry.key} 句译文长度异常（原文 ${source.length} 字）',
            level: QualityLevel.warning,
            reference: '${entry.key}',
          ),
        );
      } else if (ratio < 0.18) {
        issues.add(
          QualityIssue(
            code: 'suspiciously_short',
            message: '第 ${entry.key} 句译文过短，可能截断',
            level: QualityLevel.warning,
            reference: '${entry.key}',
          ),
        );
      }
      if (RegExp(
        r'(\.\.\.|…|\[|【|（待补）|TODO)',
        caseSensitive: false,
      ).hasMatch(text)) {
        issues.add(
          QualityIssue(
            code: 'placeholder',
            message: '第 ${entry.key} 句译文包含占位符或省略号',
            level: QualityLevel.warning,
            reference: '${entry.key}',
          ),
        );
      }
    }
    final repeated = <String, int>{};
    for (final text in translations.values) {
      final key = text.trim();
      if (key.length < 2) continue;
      repeated[key] = (repeated[key] ?? 0) + 1;
    }
    for (final entry in repeated.entries) {
      if (entry.value >= 4) {
        issues.add(
          QualityIssue(
            code: 'repeated_translation',
            message: '同一译文重复出现 ${entry.value} 次：${entry.key}',
            level: QualityLevel.warning,
          ),
        );
      }
    }
    final untranslated = issues
        .where((issue) => issue.code == 'untranslated')
        .length;
    if (untranslated >= 3 &&
        originals.isNotEmpty &&
        untranslated / originals.length > 0.3) {
      issues.add(
        const QualityIssue(
          code: 'untranslated_batch',
          message: '超过 30% 的句子疑似未翻译',
          level: QualityLevel.needsReview,
        ),
      );
    }
    return QualityReport(level: _level(issues), issues: issues);
  }

  QualityReport checkKnowledge(Map<String, dynamic> data) {
    final issues = <QualityIssue>[];
    final entities = (data['entities'] as List? ?? const []).whereType<Map>();
    final relations = (data['relations'] as List? ?? const []).whereType<Map>();
    final events = (data['events'] as List? ?? const []).whereType<Map>();
    final ids = <int>{};
    final names = <String, int>{};
    for (final entity in entities) {
      final id = _asInt(entity['id']);
      final name = '${entity['name'] ?? ''}'.trim();
      if (id == null) {
        issues.add(
          const QualityIssue(
            code: 'invalid_entity_id',
            message: '实体缺少有效 id',
            level: QualityLevel.failed,
          ),
        );
        continue;
      }
      if (!ids.add(id)) {
        issues.add(
          QualityIssue(
            code: 'duplicate_entity_id',
            message: '实体 id $id 重复',
            level: QualityLevel.failed,
            reference: '$id',
          ),
        );
      }
      if (name.isEmpty) {
        issues.add(
          QualityIssue(
            code: 'empty_entity_name',
            message: '实体 $id 名称为空',
            level: QualityLevel.failed,
            reference: '$id',
          ),
        );
      } else if (names.containsKey(name)) {
        issues.add(
          QualityIssue(
            code: 'duplicate_entity_name',
            message: '本块内实体“$name”重复出现',
            level: QualityLevel.warning,
            reference: '$id',
          ),
        );
      }
      names[name] = id;
      final evidence = entity['evidence'];
      if (evidence is! List || evidence.isEmpty) {
        issues.add(
          QualityIssue(
            code: 'entity_without_evidence',
            message: '实体“$name”没有原文证据',
            level: QualityLevel.needsReview,
            reference: '$id',
          ),
        );
      }
    }
    final relationKeys = <String>{};
    for (final relation in relations) {
      final from = _asInt(relation['from']);
      final to = _asInt(relation['to']);
      if (from == null ||
          to == null ||
          !ids.contains(from) ||
          !ids.contains(to)) {
        issues.add(
          QualityIssue(
            code: 'invalid_relation_endpoint',
            message: '关系端点无效：${relation['from']} → ${relation['to']}',
            level: QualityLevel.failed,
          ),
        );
        continue;
      }
      final type = '${relation['type'] ?? ''}'.trim();
      if (type.isEmpty) {
        issues.add(
          QualityIssue(
            code: 'empty_relation_type',
            message: '关系 $from → $to 缺少类型',
            level: QualityLevel.failed,
          ),
        );
      }
      final key = '$from|$to|$type';
      if (!relationKeys.add(key)) {
        issues.add(
          QualityIssue(
            code: 'duplicate_relation',
            message: '关系 $from → $to（$type）重复',
            level: QualityLevel.warning,
          ),
        );
      }
      final evidence = relation['evidence'];
      if (evidence is! List || evidence.isEmpty) {
        issues.add(
          QualityIssue(
            code: 'relation_without_evidence',
            message: '关系 $from → $to 没有原文证据',
            level: QualityLevel.needsReview,
          ),
        );
      }
    }
    for (final event in events) {
      final name = '${event['name'] ?? ''}'.trim();
      if (name.isEmpty) {
        issues.add(
          const QualityIssue(
            code: 'empty_event_name',
            message: '事件名称为空',
            level: QualityLevel.failed,
          ),
        );
      }
      final evidence = event['evidence'];
      if (evidence is! List || evidence.isEmpty) {
        issues.add(
          QualityIssue(
            code: 'event_without_evidence',
            message: '事件“$name”没有原文证据',
            level: QualityLevel.needsReview,
          ),
        );
      }
      final year = _asInt(event['year']);
      if (year != null && (year < -3000 || year > 2200)) {
        issues.add(
          QualityIssue(
            code: 'implausible_event_year',
            message: '事件“$name”年份异常：$year',
            level: QualityLevel.warning,
          ),
        );
      }
    }
    return QualityReport(level: _level(issues), issues: issues);
  }

  static QualityLevel _level(List<QualityIssue> issues) {
    if (issues.any((issue) => issue.level == QualityLevel.failed)) {
      return QualityLevel.failed;
    }
    if (issues.any((issue) => issue.level == QualityLevel.needsReview)) {
      return QualityLevel.needsReview;
    }
    if (issues.any((issue) => issue.level == QualityLevel.warning)) {
      return QualityLevel.warning;
    }
    return QualityLevel.passed;
  }

  static int? _asInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }
}
