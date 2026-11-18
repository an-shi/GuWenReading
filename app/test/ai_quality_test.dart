import 'package:flutter_test/flutter_test.dart';
import 'package:guwenreader/core/local/quality_service.dart';

void main() {
  test(
    'translation quality detects missing, empty and untranslated output',
    () {
      const service = QualityService();
      final report = service.checkTranslations(
        translations: {1: '译文一', 2: '', 4: '甲乙丙'},
        originals: {1: '甲乙', 2: '丙丁', 3: '戊己', 4: '甲乙丙'},
      );
      expect(report.level, QualityLevel.failed);
      expect(
        report.issues.any((issue) => issue.code == 'missing_translation'),
        isTrue,
      );
      expect(
        report.issues.any((issue) => issue.code == 'empty_translation'),
        isTrue,
      );
      expect(
        report.issues.any((issue) => issue.code == 'untranslated'),
        isTrue,
      );
    },
  );

  test('clean translation passes', () {
    const service = QualityService();
    final report = service.checkTranslations(
      translations: {1: '这是译文', 2: '这是第二句译文'},
      originals: {1: '甲乙丙', 2: '丁戊己'},
    );
    expect(report.level, QualityLevel.passed);
    expect(report.issues, isEmpty);
  });

  test('knowledge quality checks ids, endpoints, evidence and years', () {
    const service = QualityService();
    final bad = service.checkKnowledge({
      'entities': [
        {
          'id': 1,
          'name': '张三',
          'type': 'person',
          'evidence': [1],
        },
        {'id': 1, 'name': '李四', 'type': 'person'},
      ],
      'relations': [
        {
          'from': 1,
          'to': 9,
          'type': '君臣关系',
          'evidence': [1],
        },
        {'from': 1, 'to': 2, 'type': '亲属关系'},
      ],
      'events': [
        {'name': '测试事件', 'type': 'war', 'year': 99999},
      ],
    });
    expect(bad.level, QualityLevel.failed);
    expect(
      bad.issues.any((issue) => issue.code == 'duplicate_entity_id'),
      isTrue,
    );
    expect(
      bad.issues.any((issue) => issue.code == 'invalid_relation_endpoint'),
      isTrue,
    );
    expect(
      bad.issues.any((issue) => issue.code == 'empty_event_name') ||
          bad.issues.any((issue) => issue.code == 'implausible_event_year'),
      isTrue,
    );

    final good = service.checkKnowledge({
      'entities': [
        {
          'id': 1,
          'name': '张三',
          'type': 'person',
          'evidence': [1],
        },
        {
          'id': 2,
          'name': '李四',
          'type': 'person',
          'evidence': [2],
        },
      ],
      'relations': [
        {
          'from': 1,
          'to': 2,
          'type': '君臣关系',
          'evidence': [1],
        },
      ],
      'events': [
        {
          'name': '测试事件',
          'type': 'war',
          'year': 200,
          'participants': [1, 2],
          'evidence': [2],
        },
      ],
    });
    expect(good.level, QualityLevel.passed);
  });
}
