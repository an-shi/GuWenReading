import 'dart:math' as math;

import 'local_models.dart';

/// Where a token number came from.
///
/// `providerActual` is only used for post-request accounting. Anything computed
/// before a request is sent is either a real local tokenizer or an estimate.
enum TokenCountSource {
  providerActual('provider_actual'),
  localTokenizer('local_tokenizer'),
  localEstimate('local_estimate');

  const TokenCountSource(this.wireValue);

  final String wireValue;
}

class TokenCount {
  const TokenCount({
    required this.tokens,
    required this.source,
    required this.tokenizer,
  });

  final int tokens;
  final TokenCountSource source;
  final String tokenizer;
}

abstract class TokenizerAdapter {
  String get name;

  /// The quality level this adapter can honestly claim. Heuristic adapters
  /// must override this to [TokenCountSource.localEstimate].
  TokenCountSource get source => TokenCountSource.localTokenizer;

  TokenCount count(String text);
}

/// Model-family heuristic used before a request is sent.
///
/// Flutter does not bundle the BPE vocabularies of commercial providers, so
/// this adapter never claims to be an exact tokenizer. It keeps per-family
/// CJK/Latin ratios so context-window budgeting is conservative instead of
/// treating every model as the same character count.
class HeuristicTokenizerAdapter implements TokenizerAdapter {
  const HeuristicTokenizerAdapter({
    required this.name,
    this.cjkWeight = 1,
    this.asciiCharsPerToken = 4,
    this.includeWhitespace = true,
  });

  @override
  final String name;
  final double cjkWeight;
  final double asciiCharsPerToken;
  final bool includeWhitespace;

  @override
  TokenCountSource get source => TokenCountSource.localEstimate;

  @override
  TokenCount count(String text) {
    if (text.isEmpty) {
      return TokenCount(
        tokens: 0,
        source: TokenCountSource.localEstimate,
        tokenizer: name,
      );
    }
    var cjk = 0;
    var latin = 0;
    var digits = 0;
    var punctuation = 0;
    var spaces = 0;
    for (final rune in text.runes) {
      if (_isCjk(rune)) {
        cjk += 1;
      } else if (rune >= 0x30 && rune <= 0x39) {
        digits += 1;
      } else if (_isAsciiLetter(rune)) {
        latin += 1;
      } else if (rune == 0x20 || rune == 0x09 || rune == 0x0A || rune == 0x0D) {
        spaces += 1;
      } else {
        punctuation += 1;
      }
    }
    final latinTokens = latin / asciiCharsPerToken;
    final digitTokens = digits / 3;
    // CJK punctuation is usually one token per mark, while ASCII punctuation
    // is often merged with neighbouring bytes. Keep a conservative value.
    final punctuationTokens = punctuation * 0.6;
    final spaceTokens = includeWhitespace ? spaces * 0.15 : 0.0;
    final estimated =
        cjk * cjkWeight +
        latinTokens +
        digitTokens +
        punctuationTokens +
        spaceTokens;
    return TokenCount(
      tokens: math.max(1, estimated.ceil()),
      source: TokenCountSource.localEstimate,
      tokenizer: name,
    );
  }

  static bool _isAsciiLetter(int rune) =>
      (rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A);

  static bool _isCjk(int rune) =>
      (rune >= 0x3400 && rune <= 0x9FFF) ||
      (rune >= 0xF900 && rune <= 0xFAFF) ||
      (rune >= 0x20000 && rune <= 0x2FA1F) ||
      (rune >= 0x3000 && rune <= 0x303F);
}

/// Resolves a tokenizer per model.
///
/// Real local tokenizers can be registered with [register] without changing
/// translation/knowledge business code. When no exact tokenizer is registered,
/// a model-family heuristic is returned and [TokenCount.source] is
/// `localEstimate`.
class TokenizerRegistry {
  const TokenizerRegistry._();

  static final Map<String, TokenizerAdapter> _registered = {};

  /// Registers a real local tokenizer under keys such as `cl100k_base`.
  static void register(String key, TokenizerAdapter adapter) {
    _registered[key.toLowerCase()] = adapter;
  }

  static void unregister(String key) {
    _registered.remove(key.toLowerCase());
  }

  static List<String> get registeredKeys => _registered.keys.toList()..sort();

  static TokenizerAdapter forModel(AiModelRecord model) {
    final configured = model.tokenizer?.trim().toLowerCase();
    if (configured != null && configured.isNotEmpty) {
      final exact = _registered[configured];
      if (exact != null) return exact;
      final family = _heuristicForKey(configured);
      if (family != null) return family;
    }
    final id = '${model.name} ${model.displayName}'.toLowerCase();
    if (id.contains('claude') || id.contains('anthropic')) {
      return _anthropic();
    }
    if (id.contains('gemini') || id.contains('gemma')) {
      return _gemini();
    }
    if (id.contains('qwen') || id.contains('通义') || id.contains('qwq')) {
      return _qwen();
    }
    if (id.contains('deepseek')) {
      return _deepseek();
    }
    if (id.contains('gpt') ||
        id.contains('openai') ||
        id.contains('chatgpt') ||
        id.contains('o1') ||
        id.contains('o3') ||
        id.contains('o4')) {
      return _openAi();
    }
    return const HeuristicTokenizerAdapter(
      name: 'generic-heuristic',
      cjkWeight: 1,
      asciiCharsPerToken: 4,
    );
  }

  static int estimateTokens(AiModelRecord model, String text) =>
      forModel(model).count(text).tokens;

  static TokenizerAdapter? _heuristicForKey(String key) {
    final normalized = key.replaceAll('-', '_');
    if (normalized.startsWith('cl100k') || normalized == 'openai') {
      return const HeuristicTokenizerAdapter(
        name: 'openai-cl100k-heuristic',
        cjkWeight: 0.95,
        asciiCharsPerToken: 3.8,
      );
    }
    if (normalized.startsWith('o200k') || normalized == 'gpt4o') {
      return const HeuristicTokenizerAdapter(
        name: 'openai-o200k-heuristic',
        cjkWeight: 0.9,
        asciiCharsPerToken: 4.1,
      );
    }
    if (normalized == 'qwen' || normalized == 'qwen2') {
      return const HeuristicTokenizerAdapter(
        name: 'qwen-heuristic',
        cjkWeight: 1,
        asciiCharsPerToken: 3.6,
      );
    }
    if (normalized == 'deepseek') {
      return const HeuristicTokenizerAdapter(
        name: 'deepseek-heuristic',
        cjkWeight: 1,
        asciiCharsPerToken: 4,
      );
    }
    if (normalized == 'anthropic' || normalized == 'claude') {
      return const HeuristicTokenizerAdapter(
        name: 'anthropic-heuristic',
        cjkWeight: 1.15,
        asciiCharsPerToken: 3.8,
      );
    }
    if (normalized == 'gemini' || normalized == 'gemma') {
      return const HeuristicTokenizerAdapter(
        name: 'gemini-heuristic',
        cjkWeight: 0.95,
        asciiCharsPerToken: 4,
      );
    }
    if (normalized == 'generic' || normalized == 'estimate') {
      return const HeuristicTokenizerAdapter(
        name: 'generic-heuristic',
        cjkWeight: 1,
        asciiCharsPerToken: 4,
      );
    }
    return null;
  }

  static TokenizerAdapter _anthropic() => const HeuristicTokenizerAdapter(
    name: 'anthropic-heuristic',
    cjkWeight: 1.15,
    asciiCharsPerToken: 3.8,
  );

  static TokenizerAdapter _gemini() => const HeuristicTokenizerAdapter(
    name: 'gemini-heuristic',
    cjkWeight: 0.95,
    asciiCharsPerToken: 4,
  );

  static TokenizerAdapter _qwen() => const HeuristicTokenizerAdapter(
    name: 'qwen-heuristic',
    cjkWeight: 1,
    asciiCharsPerToken: 3.6,
  );

  static TokenizerAdapter _deepseek() => const HeuristicTokenizerAdapter(
    name: 'deepseek-heuristic',
    cjkWeight: 1,
    asciiCharsPerToken: 4,
  );

  static TokenizerAdapter _openAi() => const HeuristicTokenizerAdapter(
    name: 'openai-heuristic',
    cjkWeight: 0.95,
    asciiCharsPerToken: 3.9,
  );
}
