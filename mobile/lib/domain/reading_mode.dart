enum ReaderMode {
  alternating,
  originalFirst,
  independent,
  sentence;

  String get key => switch (this) {
        ReaderMode.alternating => 'alternating',
        ReaderMode.originalFirst => 'original',
        ReaderMode.independent => 'independent',
        ReaderMode.sentence => 'sentence',
      };

  String get label => switch (this) {
        ReaderMode.alternating => '原文译文交替',
        ReaderMode.originalFirst => '原文优先',
        ReaderMode.independent => '原文/译文切换',
        ReaderMode.sentence => '逐句对照',
      };

  String get shortLabel => switch (this) {
        ReaderMode.alternating => '交替',
        ReaderMode.originalFirst => '原文',
        ReaderMode.independent => '切换',
        ReaderMode.sentence => '逐句',
      };

  static ReaderMode fromKey(String? key) => switch (key) {
        'original' => ReaderMode.originalFirst,
        'independent' => ReaderMode.independent,
        'sentence' => ReaderMode.sentence,
        _ => ReaderMode.alternating,
      };
}

enum IndependentSide { original, translation }

String stateLabel(String state) => switch (state) {
      'pending' => '未翻译',
      'queued' => '排队中',
      'translating' => '翻译中',
      'completed' => '已翻译',
      'failed' => '翻译失败',
      _ => '未知',
    };
