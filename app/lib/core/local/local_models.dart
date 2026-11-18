class AiProviderRecord {
  const AiProviderRecord({
    required this.id,
    required this.name,
    required this.kind,
    required this.baseUrl,
    this.notes,
    this.enabled = true,
    this.apiKey = '',
  });

  final String id;
  final String name;
  final String kind;
  final String baseUrl;
  final String? notes;
  final bool enabled;
  final String apiKey;

  factory AiProviderRecord.fromRow(
    Map<String, Object?> row, {
    String apiKey = '',
  }) => AiProviderRecord(
    id: row['id'] as String,
    name: row['name'] as String,
    kind: row['kind'] as String? ?? 'openai_compatible',
    baseUrl: row['base_url'] as String? ?? '',
    notes: row['notes'] as String?,
    enabled: (row['enabled'] as int? ?? 1) == 1,
    apiKey: apiKey,
  );
}

class AiModelRecord {
  const AiModelRecord({
    required this.id,
    required this.providerId,
    required this.name,
    required this.displayName,
    this.contextWindow = 8192,
    this.maxOutputTokens = 2048,
    this.timeoutSeconds = 120,
    this.capabilities = const ['translation', 'chat'],
    this.supportsJson = true,
    this.isDefaultTranslation = false,
    this.isDefaultChat = false,
    this.isDefaultExtraction = false,
    this.inputPrice = 0,
    this.outputPrice = 0,
    this.cacheReadPrice = 0,
    this.cacheWritePrice = 0,
    this.tokenizer,
    this.enabled = true,
  });

  final String id;
  final String providerId;
  final String name;
  final String displayName;
  final int contextWindow;
  final int maxOutputTokens;
  final int timeoutSeconds;
  final List<String> capabilities;
  final bool supportsJson;
  final bool isDefaultTranslation;
  final bool isDefaultChat;
  final bool isDefaultExtraction;

  /// Price per one million tokens. The currency is user-defined and should be
  /// kept consistent across models used for cost comparisons.
  final double inputPrice;
  final double outputPrice;
  final double cacheReadPrice;
  final double cacheWritePrice;

  /// Optional tokenizer family override, e.g. `cl100k_base`, `o200k_base`,
  /// `qwen`, `deepseek`, `anthropic`, `gemini`. Unknown values fall back to
  /// the model-name heuristic.
  final String? tokenizer;
  final bool enabled;

  bool supports(String capability) => capabilities.contains(capability);

  factory AiModelRecord.fromRow(Map<String, Object?> row) => AiModelRecord(
    id: row['id'] as String,
    providerId: row['provider_id'] as String,
    name: row['name'] as String,
    displayName: row['display_name'] as String? ?? row['name'] as String,
    contextWindow: row['context_window'] as int? ?? 8192,
    maxOutputTokens: row['max_output_tokens'] as int? ?? 2048,
    timeoutSeconds: row['timeout_seconds'] as int? ?? 120,
    capabilities: _stringList(row['capabilities']),
    supportsJson: (row['supports_json'] as int? ?? 1) == 1,
    isDefaultTranslation: (row['is_default_translation'] as int? ?? 0) == 1,
    isDefaultChat: (row['is_default_chat'] as int? ?? 0) == 1,
    isDefaultExtraction: (row['is_default_extraction'] as int? ?? 0) == 1,
    inputPrice: (row['input_price'] as num? ?? 0).toDouble(),
    outputPrice: (row['output_price'] as num? ?? 0).toDouble(),
    cacheReadPrice: (row['cache_read_price'] as num? ?? 0).toDouble(),
    cacheWritePrice: (row['cache_write_price'] as num? ?? 0).toDouble(),
    tokenizer: row['tokenizer'] as String?,
    enabled: (row['enabled'] as int? ?? 1) == 1,
  );
}

class PromptRecord {
  const PromptRecord({
    required this.id,
    required this.key,
    required this.version,
    required this.name,
    this.description,
    required this.template,
    this.variables = const [],
    this.isActive = false,
    this.createdAt,
  });

  final String id;
  final String key;
  final int version;
  final String name;
  final String? description;
  final String template;
  final List<String> variables;
  final bool isActive;
  final String? createdAt;

  factory PromptRecord.fromRow(Map<String, Object?> row) => PromptRecord(
    id: row['id'] as String,
    key: row['key'] as String,
    version: row['version'] as int? ?? 1,
    name: row['name'] as String? ?? '',
    description: row['description'] as String?,
    template: row['template'] as String? ?? '',
    variables: _stringList(row['variables']),
    isActive: (row['is_active'] as int? ?? 0) == 1,
    createdAt: row['created_at'] as String?,
  );
}

List<String> _stringList(Object? value) {
  if (value is List) return value.map((item) => '$item').toList();
  if (value is String && value.trim().isNotEmpty) {
    try {
      final decoded = value;
      if (decoded.startsWith('[')) {
        return decoded
            .replaceAll(RegExp(r'[\[\]"]'), '')
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();
      }
    } catch (_) {
      // Fall through to a single value.
    }
    return [value];
  }
  return const [];
}

class SearchSentenceHit {
  const SearchSentenceHit({
    required this.sentenceId,
    required this.bookId,
    required this.bookTitle,
    required this.chapterId,
    required this.chapterTitle,
    required this.text,
    required this.docType,
    this.originalText,
  });

  final String sentenceId;
  final String bookId;
  final String bookTitle;
  final String chapterId;
  final String chapterTitle;
  final String text;
  final String docType;
  final String? originalText;
}

class SearchEntityHit {
  const SearchEntityHit({
    required this.id,
    required this.name,
    required this.kind,
    this.dynasty,
    this.summary,
    this.status = 'pending',
  });

  final String id;
  final String name;
  final String kind;
  final String? dynasty;
  final String? summary;
  final String status;
}

class SearchEventHit {
  const SearchEventHit({
    required this.id,
    required this.name,
    required this.eventType,
    this.timeRaw,
    this.timeStartYear,
    this.status = 'extracted',
  });

  final String id;
  final String name;
  final String eventType;
  final String? timeRaw;
  final int? timeStartYear;
  final String status;
}

class LocalSearchResults {
  const LocalSearchResults({
    this.sentences = const [],
    this.entities = const [],
    this.events = const [],
  });

  final List<SearchSentenceHit> sentences;
  final List<SearchEntityHit> entities;
  final List<SearchEventHit> events;

  int get total => sentences.length + entities.length + events.length;
}

class GraphNode {
  const GraphNode({
    required this.id,
    required this.label,
    required this.kind,
    this.dynasty,
    this.status,
    this.degree = 0,
  });
  final String id;
  final String label;
  final String kind;
  final String? dynasty;
  final String? status;
  final int degree;
}

class GraphEdge {
  const GraphEdge({
    required this.id,
    required this.source,
    required this.target,
    required this.relationType,
    this.label,
    this.status = 'inferred',
  });
  final String id;
  final String source;
  final String target;
  final String relationType;
  final String? label;
  final String status;
}

class LocalGraphData {
  const LocalGraphData({
    this.nodes = const [],
    this.edges = const [],
    this.centerId,
  });
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final String? centerId;
}

class AiUsageRecord {
  const AiUsageRecord({
    required this.id,
    required this.taskType,
    required this.inputTokens,
    required this.outputTokens,
    required this.cacheReadTokens,
    required this.cacheWriteTokens,
    required this.totalTokens,
    required this.cost,
    required this.durationMs,
    required this.status,
    required this.isEstimated,
    required this.createdAt,
    this.tokenSource = 'provider_actual',
    this.taskId,
    this.providerId,
    this.providerName,
    this.modelId,
    this.modelName,
    this.retryCount = 0,
    this.error,
  });

  final String id;
  final String? taskId;
  final String taskType;
  final String? providerId;
  final String? providerName;
  final String? modelId;
  final String? modelName;
  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final int totalTokens;
  final double cost;
  final int durationMs;
  final String status;
  final int retryCount;
  final bool isEstimated;
  final String tokenSource;
  final String? error;
  final String createdAt;

  factory AiUsageRecord.fromRow(Map<String, Object?> row) => AiUsageRecord(
    id: row['id'] as String,
    taskId: row['task_id'] as String?,
    taskType: row['task_type'] as String? ?? 'other',
    providerId: row['provider_id'] as String?,
    providerName: row['provider_name'] as String?,
    modelId: row['model_id'] as String?,
    modelName: row['model_name'] as String?,
    inputTokens: row['input_tokens'] as int? ?? 0,
    outputTokens: row['output_tokens'] as int? ?? 0,
    cacheReadTokens: row['cache_read_tokens'] as int? ?? 0,
    cacheWriteTokens: row['cache_write_tokens'] as int? ?? 0,
    totalTokens: row['total_tokens'] as int? ?? 0,
    cost: (row['cost'] as num? ?? 0).toDouble(),
    durationMs: row['duration_ms'] as int? ?? 0,
    status: row['status'] as String? ?? 'success',
    retryCount: row['retry_count'] as int? ?? 0,
    isEstimated: (row['is_estimated'] as int? ?? 0) == 1,
    tokenSource: row['token_source'] as String? ?? 'provider_actual',
    error: row['error'] as String?,
    createdAt: row['created_at'] as String? ?? '',
  );
}

class AiUsageGroup {
  const AiUsageGroup({
    required this.label,
    required this.requests,
    required this.inputTokens,
    required this.outputTokens,
    required this.cacheReadTokens,
    required this.cacheWriteTokens,
    required this.cost,
  });

  final String label;
  final int requests;
  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final double cost;
}

class AiUsageSummary {
  const AiUsageSummary({
    this.requests = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadTokens = 0,
    this.cacheWriteTokens = 0,
    this.cost = 0,
    this.estimatedRequests = 0,
    this.byType = const [],
    this.byModel = const [],
  });

  final int requests;
  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final double cost;
  final int estimatedRequests;
  final List<AiUsageGroup> byType;
  final List<AiUsageGroup> byModel;
}
