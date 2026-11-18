import 'package:flutter_test/flutter_test.dart';
import 'package:guwenreader/core/local/local_models.dart';
import 'package:guwenreader/core/local/tokenizer_adapter.dart';

AiModelRecord _model(String name, {String? tokenizer}) => AiModelRecord(
  id: 'm-$name',
  providerId: 'p',
  name: name,
  displayName: name,
  tokenizer: tokenizer,
);

void main() {
  test('model families resolve to different tokenizer adapters', () {
    final gpt = TokenizerRegistry.forModel(_model('gpt-4o'));
    final claude = TokenizerRegistry.forModel(_model('claude-3-5-sonnet'));
    final qwen = TokenizerRegistry.forModel(_model('qwen-max'));
    final deepseek = TokenizerRegistry.forModel(_model('deepseek-chat'));
    final gemini = TokenizerRegistry.forModel(_model('gemini-2.0-flash'));
    final unknown = TokenizerRegistry.forModel(_model('local-model'));

    expect(gpt.name, 'openai-heuristic');
    expect(claude.name, 'anthropic-heuristic');
    expect(qwen.name, 'qwen-heuristic');
    expect(deepseek.name, 'deepseek-heuristic');
    expect(gemini.name, 'gemini-heuristic');
    expect(unknown.name, 'generic-heuristic');

    expect(gpt.source, TokenCountSource.localEstimate);
    expect(claude.source, TokenCountSource.localEstimate);
  });

  test('configured tokenizer overrides the model-name heuristic', () {
    final configured = TokenizerRegistry.forModel(
      _model('unknown-model', tokenizer: 'qwen'),
    );
    expect(configured.name, 'qwen-heuristic');

    final cl100k = TokenizerRegistry.forModel(
      _model('deepseek-chat', tokenizer: 'cl100k_base'),
    );
    expect(cl100k.name, 'openai-cl100k-heuristic');
  });

  test('registered local tokenizer is used and reported as localTokenizer', () {
    TokenizerRegistry.register(
      'test-exact',
      const _FixedTokenizer(name: 'test-exact'),
    );
    addTearDown(() => TokenizerRegistry.unregister('test-exact'));

    final adapter = TokenizerRegistry.forModel(
      _model('any', tokenizer: 'test-exact'),
    );
    final count = adapter.count('任意文本');
    expect(count.tokens, 7);
    expect(count.source, TokenCountSource.localTokenizer);
    expect(count.tokenizer, 'test-exact');
  });

  test('CJK text and Latin text use different ratios', () {
    final model = _model('gpt-4o');
    final cjk = TokenizerRegistry.estimateTokens(model, '黄帝者少典之子');
    final latin = TokenizerRegistry.estimateTokens(model, 'abcdefgh');
    expect(cjk, greaterThanOrEqualTo(7));
    expect(latin, lessThan(cjk));
  });

  test('empty text counts as zero', () {
    final adapter = TokenizerRegistry.forModel(_model('gpt-4o'));
    expect(adapter.count('').tokens, 0);
  });
}

class _FixedTokenizer implements TokenizerAdapter {
  const _FixedTokenizer({required this.name});

  @override
  final String name;

  @override
  TokenCountSource get source => TokenCountSource.localTokenizer;

  @override
  TokenCount count(String text) =>
      TokenCount(tokens: text.isEmpty ? 0 : 7, source: source, tokenizer: name);
}
