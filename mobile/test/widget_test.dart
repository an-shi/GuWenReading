import 'package:flutter_test/flutter_test.dart';
import 'package:guwenreading_mobile/data/models.dart';
import 'package:guwenreading_mobile/domain/reading_mode.dart';

void main() {
  test('reading modes keep stable keys', () {
    expect(ReaderMode.fromKey('original'), ReaderMode.originalFirst);
    expect(ReaderMode.fromKey('sentence'), ReaderMode.sentence);
    expect(ReaderMode.fromKey('unknown'), ReaderMode.alternating);
  });

  test('chapter content parses sentences without losing original text', () {
    final content = ChapterContent.fromJson({
      'book': {'id': 'b1', 'title': '史记'},
      'chapter': {'id': 'c1', 'ordinal': 0, 'title': '五帝本纪'},
      'translation_status': {'total': 1, 'translated': 1, 'percent': 100, 'states': {}},
      'paragraphs': [
        {
          'id': 'p1',
          'ordinal': 0,
          'original_text': '黄帝者，少典之子。',
          'sentences': [
            {
              'id': 's1',
              'ordinal': 0,
              'original_text': '黄帝者，少典之子。',
              'translation_state': 'completed',
              'translation': {
                'id': 't1',
                'sentence_id': 's1',
                'text': '黄帝是少典的儿子。',
                'origin': 'manual',
              },
            },
          ],
        },
      ],
    });
    expect(content.paragraphs.single.sentences.single.originalText, '黄帝者，少典之子。');
    expect(content.paragraphs.single.sentences.single.isManual, isTrue);
    expect(content.status.translated, 1);
  });
}
