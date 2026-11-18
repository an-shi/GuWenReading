import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import 'ai_service.dart';
import 'app_database.dart';
import 'local_models.dart';
import 'local_store.dart';

class BudgetScopeStatus {
  const BudgetScopeStatus({
    required this.label,
    required this.limit,
    required this.spent,
    required this.reserved,
  });

  final String label;
  final double limit;
  final double spent;
  final double reserved;

  double get remaining =>
      limit <= 0 ? double.infinity : limit - spent - reserved;
}

class BudgetStatus {
  const BudgetStatus({
    this.daily = const BudgetScopeStatus(
      label: '今日',
      limit: 0,
      spent: 0,
      reserved: 0,
    ),
    this.monthly = const BudgetScopeStatus(
      label: '本月',
      limit: 0,
      spent: 0,
      reserved: 0,
    ),
    this.book = const BudgetScopeStatus(
      label: '本书',
      limit: 0,
      spent: 0,
      reserved: 0,
    ),
    this.chapter = const BudgetScopeStatus(
      label: '本章',
      limit: 0,
      spent: 0,
      reserved: 0,
    ),
    this.task = const BudgetScopeStatus(
      label: '本任务',
      limit: 0,
      spent: 0,
      reserved: 0,
    ),
  });

  final BudgetScopeStatus daily;
  final BudgetScopeStatus monthly;
  final BudgetScopeStatus book;
  final BudgetScopeStatus chapter;
  final BudgetScopeStatus task;
}

class BudgetReservationResult {
  const BudgetReservationResult({required this.allowed, this.message});

  final bool allowed;
  final String? message;
}

class BudgetExceededException implements Exception {
  BudgetExceededException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Three-level cost budgets plus reservations.
///
/// Limits are stored in `ai_budget_limits`; actual spend always comes from
/// `ai_usage`, so restarts and backups do not desynchronise counters. The task
/// budget falls back to the legacy `ai_task_budget` preference when no row is
/// configured.
class BudgetService {
  BudgetService({required this.store});

  final LocalStore store;

  static const _daily = 'global_daily';
  static const _monthly = 'global_monthly';
  static const _book = 'book';
  static const _chapter = 'chapter';
  static const _task = 'task';

  Future<BudgetReservationResult> reserve({
    required String taskId,
    String? bookId,
    String? chapterId,
    required double estimatedCost,
  }) async {
    return store.db.transaction((txn) async {
      final now = DateTime.now();
      final dailyStart = DateTime(now.year, now.month, now.day);
      final monthlyStart = DateTime(now.year, now.month);
      final limits = await _limits(
        txn,
        bookId: bookId,
        chapterId: chapterId,
        taskId: taskId,
      );
      final checks = <_BudgetCheck>[
        _BudgetCheck(
          label: '今日全局预算',
          limit: limits.daily,
          spent: await _spent(txn, scope: _daily, since: dailyStart),
          reserved: await _reserved(txn, scope: _daily, since: dailyStart),
        ),
        _BudgetCheck(
          label: '本月全局预算',
          limit: limits.monthly,
          spent: await _spent(txn, scope: _monthly, since: monthlyStart),
          reserved: await _reserved(txn, scope: _monthly, since: monthlyStart),
        ),
        if (bookId != null)
          _BudgetCheck(
            label: '本书预算',
            limit: limits.book,
            spent: await _spent(txn, scope: _book, scopeId: bookId),
            reserved: await _reserved(txn, scope: _book, scopeId: bookId),
          ),
        if (chapterId != null)
          _BudgetCheck(
            label: '本章预算',
            limit: limits.chapter,
            spent: await _spent(txn, scope: _chapter, scopeId: chapterId),
            reserved: await _reserved(txn, scope: _chapter, scopeId: chapterId),
          ),
        if (limits.task > 0)
          _BudgetCheck(
            label: '本任务预算',
            limit: limits.task,
            spent: await _spent(txn, scope: _task, scopeId: taskId),
            reserved: 0,
          ),
      ];
      for (final check in checks) {
        if (!check.allows(estimatedCost)) {
          return BudgetReservationResult(
            allowed: false,
            message:
                '${check.label}不足：限额 ${check.limit.toStringAsFixed(4)}，'
                '已用 ${check.spent.toStringAsFixed(4)}，'
                '已预留 ${check.reserved.toStringAsFixed(4)}，'
                '预计需要 ${estimatedCost.toStringAsFixed(4)}',
          );
        }
      }
      await txn.insert('ai_budget_reservations', {
        'id': newLocalId('bgr'),
        'task_id': taskId,
        'book_id': bookId,
        'chapter_id': chapterId,
        'estimated_cost': estimatedCost,
        'remaining_cost': estimatedCost,
        'released': 0,
        'created_at': now.toUtc().toIso8601String(),
        'updated_at': now.toUtc().toIso8601String(),
      });
      return const BudgetReservationResult(allowed: true);
    });
  }

  /// Shrinks the reservation as real usage is recorded.
  Future<void> adjust(String taskId, double actualCost) async {
    final rows = await store.db.query(
      'ai_budget_reservations',
      where: 'task_id = ? AND released = 0',
      whereArgs: [taskId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return;
    final estimated = (rows.first['estimated_cost'] as num? ?? 0).toDouble();
    final remaining = math.max(0, estimated - actualCost);
    await store.db.update(
      'ai_budget_reservations',
      {
        'remaining_cost': remaining,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [rows.first['id']],
    );
  }

  Future<void> release(String taskId) async {
    await store.db.update(
      'ai_budget_reservations',
      {
        'remaining_cost': 0,
        'released': 1,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'task_id = ? AND released = 0',
      whereArgs: [taskId],
    );
  }

  /// Checks all budgets while a task is running. The task's own reservation is
  /// excluded because its actual spend is already part of `spent`.
  Future<String?> checkDuringTask(String taskId) async {
    final task = await store.getTask(taskId);
    if (task == null) return null;
    final reservation = await store.db.query(
      'ai_budget_reservations',
      where: 'task_id = ? AND released = 0',
      whereArgs: [taskId],
      limit: 1,
    );
    final now = DateTime.now();
    final dailyStart = DateTime(now.year, now.month, now.day);
    final monthlyStart = DateTime(now.year, now.month);
    final limits = await _limits(
      store.db,
      bookId: task.bookId,
      chapterId: task.chapterId,
      taskId: taskId,
    );
    final checks = <_BudgetCheck>[
      _BudgetCheck(
        label: '今日全局预算',
        limit: limits.daily,
        spent: await _spent(store.db, scope: _daily, since: dailyStart),
        reserved: await _reserved(
          store.db,
          scope: _daily,
          since: dailyStart,
          excludingTask: taskId,
        ),
      ),
      _BudgetCheck(
        label: '本月全局预算',
        limit: limits.monthly,
        spent: await _spent(store.db, scope: _monthly, since: monthlyStart),
        reserved: await _reserved(
          store.db,
          scope: _monthly,
          since: monthlyStart,
          excludingTask: taskId,
        ),
      ),
      if (task.bookId case final bookId?)
        _BudgetCheck(
          label: '本书预算',
          limit: limits.book,
          spent: await _spent(store.db, scope: _book, scopeId: bookId),
          reserved: await _reserved(
            store.db,
            scope: _book,
            scopeId: bookId,
            excludingTask: taskId,
          ),
        ),
      if (task.chapterId case final chapterId?)
        _BudgetCheck(
          label: '本章预算',
          limit: limits.chapter,
          spent: await _spent(store.db, scope: _chapter, scopeId: chapterId),
          reserved: await _reserved(
            store.db,
            scope: _chapter,
            scopeId: chapterId,
            excludingTask: taskId,
          ),
        ),
    ];
    if (reservation.isEmpty) {
      // No reservation (old task); fall back to the legacy task budget.
      final legacy = await readAiTaskBudget();
      if (legacy > 0 && task.cost >= legacy) {
        return '已达到单次任务费用上限（${task.cost.toStringAsFixed(4)} / '
            '${legacy.toStringAsFixed(4)}）';
      }
      return null;
    }
    if (limits.task > 0 && task.cost >= limits.task) {
      return '已达到本任务预算（${task.cost.toStringAsFixed(4)} / '
          '${limits.task.toStringAsFixed(4)}）';
    }
    for (final check in checks) {
      if (check.overLimit()) {
        return '${check.label}已达上限：限额 ${check.limit.toStringAsFixed(4)}，'
            '已用 ${check.spent.toStringAsFixed(4)}，'
            '其他任务已预留 ${check.reserved.toStringAsFixed(4)}';
      }
    }
    return null;
  }

  Future<BudgetStatus> status({
    String? bookId,
    String? chapterId,
    String? taskId,
  }) async {
    final now = DateTime.now();
    final dailyStart = DateTime(now.year, now.month, now.day);
    final monthlyStart = DateTime(now.year, now.month);
    final limits = await _limits(
      store.db,
      bookId: bookId,
      chapterId: chapterId,
      taskId: taskId,
    );
    return BudgetStatus(
      daily: BudgetScopeStatus(
        label: '今日',
        limit: limits.daily,
        spent: await _spent(store.db, scope: _daily, since: dailyStart),
        reserved: await _reserved(store.db, scope: _daily, since: dailyStart),
      ),
      monthly: BudgetScopeStatus(
        label: '本月',
        limit: limits.monthly,
        spent: await _spent(store.db, scope: _monthly, since: monthlyStart),
        reserved: await _reserved(
          store.db,
          scope: _monthly,
          since: monthlyStart,
        ),
      ),
      book: bookId == null
          ? const BudgetScopeStatus(
              label: '本书',
              limit: 0,
              spent: 0,
              reserved: 0,
            )
          : BudgetScopeStatus(
              label: '本书',
              limit: limits.book,
              spent: await _spent(store.db, scope: _book, scopeId: bookId),
              reserved: await _reserved(
                store.db,
                scope: _book,
                scopeId: bookId,
              ),
            ),
      chapter: chapterId == null
          ? const BudgetScopeStatus(
              label: '本章',
              limit: 0,
              spent: 0,
              reserved: 0,
            )
          : BudgetScopeStatus(
              label: '本章',
              limit: limits.chapter,
              spent: await _spent(
                store.db,
                scope: _chapter,
                scopeId: chapterId,
              ),
              reserved: await _reserved(
                store.db,
                scope: _chapter,
                scopeId: chapterId,
              ),
            ),
      task: taskId == null
          ? const BudgetScopeStatus(
              label: '本任务',
              limit: 0,
              spent: 0,
              reserved: 0,
            )
          : BudgetScopeStatus(
              label: '本任务',
              limit: limits.task,
              spent: await _spent(store.db, scope: _task, scopeId: taskId),
              reserved: 0,
            ),
    );
  }

  Future<void> setLimit({
    required String scope,
    String scopeId = '',
    required double limit,
  }) async {
    final value = math.max(0, limit);
    if (value == 0) {
      await store.db.delete(
        'ai_budget_limits',
        where: 'scope = ? AND scope_id = ?',
        whereArgs: [scope, scopeId],
      );
      return;
    }
    await store.db.insert('ai_budget_limits', {
      'scope': scope,
      'scope_id': scopeId,
      'limit_amount': value,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<double> limit(String scope, {String scopeId = ''}) async {
    final rows = await store.db.query(
      'ai_budget_limits',
      where: 'scope = ? AND scope_id = ?',
      whereArgs: [scope, scopeId],
      limit: 1,
    );
    if (rows.isEmpty) {
      if (scope == _task) return readAiTaskBudget();
      return 0;
    }
    return (rows.first['limit_amount'] as num? ?? 0).toDouble();
  }

  /// Estimates pre-request cost from local token counts and model prices.
  double estimateCost({
    required AiModelRecord model,
    required int inputTokens,
    required int outputTokens,
  }) => aiUsageCost(
    model,
    inputTokens: inputTokens,
    outputTokens: outputTokens,
    cacheReadTokens: 0,
    cacheWriteTokens: 0,
  );

  Future<_Limits> _limits(
    DatabaseExecutor db, {
    String? bookId,
    String? chapterId,
    String? taskId,
  }) async {
    Future<double> read(String scope, String id) async {
      final rows = await db.query(
        'ai_budget_limits',
        where: 'scope = ? AND scope_id = ?',
        whereArgs: [scope, id],
        limit: 1,
      );
      return rows.isEmpty
          ? 0
          : (rows.first['limit_amount'] as num? ?? 0).toDouble();
    }

    final daily = await read(_daily, '');
    final monthly = await read(_monthly, '');
    final book = bookId == null ? 0.0 : await read(_book, bookId);
    final chapter = chapterId == null ? 0.0 : await read(_chapter, chapterId);
    final task = taskId == null ? 0.0 : await read(_task, taskId);
    final taskDefault = await read(_task, '');
    final legacyTask = await readAiTaskBudget();
    final effectiveTask = task > 0
        ? task
        : (taskDefault > 0 ? taskDefault : legacyTask);
    return _Limits(
      daily: daily,
      monthly: monthly,
      book: book,
      chapter: chapter,
      task: effectiveTask,
    );
  }

  Future<double> _spent(
    DatabaseExecutor db, {
    required String scope,
    String? scopeId,
    DateTime? since,
  }) async {
    switch (scope) {
      case _daily:
      case _monthly:
        final rows = await db.rawQuery(
          '''
          SELECT COALESCE(SUM(cost), 0) AS value FROM ai_usage
          WHERE created_at >= ?
          ''',
          [(since ?? DateTime.now()).toUtc().toIso8601String()],
        );
        return (rows.first['value'] as num? ?? 0).toDouble();
      case _book:
        final rows = await db.rawQuery(
          '''
          SELECT COALESCE(SUM(u.cost), 0) AS value
          FROM ai_usage u JOIN tasks t ON t.id = u.task_id
          WHERE t.book_id = ?
          ''',
          [scopeId],
        );
        return (rows.first['value'] as num? ?? 0).toDouble();
      case _chapter:
        final rows = await db.rawQuery(
          '''
          SELECT COALESCE(SUM(u.cost), 0) AS value
          FROM ai_usage u JOIN tasks t ON t.id = u.task_id
          WHERE t.chapter_id = ?
          ''',
          [scopeId],
        );
        return (rows.first['value'] as num? ?? 0).toDouble();
      case _task:
        final rows = await db.rawQuery(
          'SELECT COALESCE(SUM(cost), 0) AS value FROM ai_usage WHERE task_id = ?',
          [scopeId],
        );
        return (rows.first['value'] as num? ?? 0).toDouble();
      default:
        return 0;
    }
  }

  Future<double> _reserved(
    DatabaseExecutor db, {
    required String scope,
    String? scopeId,
    DateTime? since,
    String? excludingTask,
  }) async {
    String where;
    List<Object?> args;
    switch (scope) {
      case _daily:
      case _monthly:
        where = 'released = 0 AND created_at >= ?';
        args = [(since ?? DateTime.now()).toUtc().toIso8601String()];
      case _book:
        where = 'released = 0 AND book_id = ?';
        args = [scopeId];
      case _chapter:
        where = 'released = 0 AND chapter_id = ?';
        args = [scopeId];
      default:
        return 0;
    }
    if (excludingTask != null) {
      where += ' AND task_id <> ?';
      args = [...args, excludingTask];
    }
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(remaining_cost), 0) AS value '
      'FROM ai_budget_reservations WHERE $where',
      args,
    );
    return (rows.first['value'] as num? ?? 0).toDouble();
  }

  static const scopeDaily = _daily;
  static const scopeMonthly = _monthly;
  static const scopeBook = _book;
  static const scopeChapter = _chapter;
  static const scopeTask = _task;
}

class _Limits {
  const _Limits({
    required this.daily,
    required this.monthly,
    required this.book,
    required this.chapter,
    required this.task,
  });

  final double daily;
  final double monthly;
  final double book;
  final double chapter;
  final double task;
}

class _BudgetCheck {
  const _BudgetCheck({
    required this.label,
    required this.limit,
    required this.spent,
    required this.reserved,
  });

  final String label;
  final double limit;
  final double spent;
  final double reserved;

  bool allows(double estimate) =>
      limit <= 0 || spent + reserved + estimate <= limit + 1e-9;

  bool overLimit() => limit > 0 && spent + reserved >= limit - 1e-9;
}
