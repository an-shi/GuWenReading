import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'local_store.dart';

/// Identifies the current process. Tasks carrying another owner after startup
/// are leftovers from a previous run and can be safely marked interrupted.
final String appInstanceId =
    'app-${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}';

class AiSchedulerConfig {
  const AiSchedulerConfig({
    this.globalConcurrency = 2,
    this.providerConcurrency = 1,
    this.modelConcurrency = 1,
    this.taskConcurrency = 1,
    this.minRequestIntervalMs = 250,
    this.maxRetries = 3,
    this.baseBackoffMs = 800,
    this.maxBackoffMs = 15000,
  });

  final int globalConcurrency;
  final int providerConcurrency;
  final int modelConcurrency;
  final int taskConcurrency;
  final int minRequestIntervalMs;
  final int maxRetries;
  final int baseBackoffMs;
  final int maxBackoffMs;

  AiSchedulerConfig copyWith({
    int? globalConcurrency,
    int? providerConcurrency,
    int? modelConcurrency,
    int? taskConcurrency,
    int? minRequestIntervalMs,
    int? maxRetries,
    int? baseBackoffMs,
    int? maxBackoffMs,
  }) => AiSchedulerConfig(
    globalConcurrency: globalConcurrency ?? this.globalConcurrency,
    providerConcurrency: providerConcurrency ?? this.providerConcurrency,
    modelConcurrency: modelConcurrency ?? this.modelConcurrency,
    taskConcurrency: taskConcurrency ?? this.taskConcurrency,
    minRequestIntervalMs: minRequestIntervalMs ?? this.minRequestIntervalMs,
    maxRetries: maxRetries ?? this.maxRetries,
    baseBackoffMs: baseBackoffMs ?? this.baseBackoffMs,
    maxBackoffMs: maxBackoffMs ?? this.maxBackoffMs,
  );

  Map<String, Object?> toJson() => {
    'global_concurrency': globalConcurrency,
    'provider_concurrency': providerConcurrency,
    'model_concurrency': modelConcurrency,
    'task_concurrency': taskConcurrency,
    'min_request_interval_ms': minRequestIntervalMs,
    'max_retries': maxRetries,
    'base_backoff_ms': baseBackoffMs,
    'max_backoff_ms': maxBackoffMs,
  };

  factory AiSchedulerConfig.fromJson(Map<String, dynamic> json) =>
      AiSchedulerConfig(
        globalConcurrency: _int(json['global_concurrency'], 2),
        providerConcurrency: _int(json['provider_concurrency'], 1),
        modelConcurrency: _int(json['model_concurrency'], 1),
        taskConcurrency: _int(json['task_concurrency'], 1),
        minRequestIntervalMs: _int(json['min_request_interval_ms'], 250),
        maxRetries: _int(json['max_retries'], 3),
        baseBackoffMs: _int(json['base_backoff_ms'], 800),
        maxBackoffMs: _int(json['max_backoff_ms'], 15000),
      );

  static int _int(Object? value, int fallback) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    return parsed == null || parsed < 0 ? fallback : parsed;
  }
}

/// Global request scheduler shared by translation, extraction, disambiguation
/// and connection tests. It limits concurrent HTTP calls, not task objects.
class AiScheduler {
  AiScheduler._();

  static final AiScheduler instance = AiScheduler._();

  static const _settingKey = 'ai_scheduler_config';

  AiSchedulerConfig _config = const AiSchedulerConfig();
  AiSchedulerConfig get config => _config;

  int _running = 0;
  final Map<String, int> _runningByProvider = {};
  final Map<String, int> _runningByModel = {};
  final Map<String, int> _runningByTask = {};
  final Map<String, DateTime> _lastStartByProvider = {};
  final List<_ScheduledJob> _queue = [];
  bool _drainScheduled = false;

  Future<void> loadConfig(LocalStore store) async {
    final raw = await store.getSetting(_settingKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      _config = AiSchedulerConfig.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      // Keep defaults if the stored configuration is corrupt.
    }
  }

  Future<void> saveConfig(LocalStore store, AiSchedulerConfig config) async {
    _config = config;
    await store.setSetting(_settingKey, jsonEncode(config.toJson()));
  }

  /// Applies a configuration without persisting it. Used by tests and by the
  /// startup path after [loadConfig] has already restored persisted values.
  void setConfig(AiSchedulerConfig config) {
    _config = config;
  }

  Future<T> run<T>({
    required String providerId,
    required String modelId,
    String? taskId,
    int priority = 50,
    required Future<T> Function() action,
  }) {
    final completer = Completer<T>();
    _queue.add(
      _ScheduledJob(
        providerId: providerId,
        modelId: modelId,
        taskId: taskId,
        priority: priority,
        action: () async {
          try {
            completer.complete(await action());
          } catch (error, stack) {
            completer.completeError(error, stack);
          }
        },
      ),
    );
    _queue.sort((a, b) => a.priority.compareTo(b.priority));
    _drain();
    return completer.future;
  }

  void _drain() {
    if (_drainScheduled) return;
    while (_queue.isNotEmpty) {
      final index = _queue.indexWhere(_canStart);
      if (index < 0) {
        _scheduleDrain();
        return;
      }
      final job = _queue.removeAt(index);
      _start(job);
    }
  }

  bool _canStart(_ScheduledJob job) {
    if (_running >= _config.globalConcurrency) return false;
    if ((_runningByProvider[job.providerId] ?? 0) >=
        _config.providerConcurrency) {
      return false;
    }
    if ((_runningByModel[job.modelId] ?? 0) >= _config.modelConcurrency) {
      return false;
    }
    final taskId = job.taskId;
    if (taskId != null &&
        (_runningByTask[taskId] ?? 0) >= _config.taskConcurrency) {
      return false;
    }
    final last = _lastStartByProvider[job.providerId];
    if (last != null &&
        DateTime.now().difference(last).inMilliseconds <
            _config.minRequestIntervalMs) {
      return false;
    }
    return true;
  }

  void _start(_ScheduledJob job) {
    _running += 1;
    _increment(_runningByProvider, job.providerId);
    _increment(_runningByModel, job.modelId);
    if (job.taskId != null) _increment(_runningByTask, job.taskId!);
    _lastStartByProvider[job.providerId] = DateTime.now();
    unawaited(() async {
      try {
        await job.action();
      } finally {
        _running -= 1;
        _decrement(_runningByProvider, job.providerId);
        _decrement(_runningByModel, job.modelId);
        if (job.taskId != null) _decrement(_runningByTask, job.taskId!);
        _drain();
      }
    }());
  }

  void _scheduleDrain() {
    if (_drainScheduled) return;
    _drainScheduled = true;
    Future<void>.delayed(
      Duration(milliseconds: math.max(20, _config.minRequestIntervalMs)),
      () {
        _drainScheduled = false;
        _drain();
      },
    );
  }

  static void _increment(Map<String, int> map, String key) {
    map[key] = (map[key] ?? 0) + 1;
  }

  static void _decrement(Map<String, int> map, String key) {
    final next = (map[key] ?? 0) - 1;
    if (next <= 0) {
      map.remove(key);
    } else {
      map[key] = next;
    }
  }
}

class _ScheduledJob {
  const _ScheduledJob({
    required this.providerId,
    required this.modelId,
    required this.taskId,
    required this.priority,
    required this.action,
  });

  final String providerId;
  final String modelId;
  final String? taskId;
  final int priority;
  final Future<void> Function() action;
}
