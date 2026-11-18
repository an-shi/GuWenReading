import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guwenreader/core/local/app_database.dart';
import 'package:guwenreader/core/local/budget_service.dart';
import 'package:guwenreader/core/local/import_service.dart';
import 'package:guwenreader/core/local/local_store.dart';

void main() {
  test('global daily budget counts spend and active reservations', () async {
    final database = await AppDatabase.openInMemory();
    final store = LocalStore(database);
    final budgets = BudgetService(store: store);
    await budgets.setLimit(scope: BudgetService.scopeDaily, limit: 0.01);
    final first = await budgets.reserve(taskId: 'task-1', estimatedCost: 0.006);
    expect(first.allowed, isTrue);
    await store.recordAiUsage(
      taskId: 'task-1',
      taskType: 'translation',
      inputTokens: 100,
      outputTokens: 50,
      cost: 0.004,
      durationMs: 100,
      status: 'success',
    );
    final second = await budgets.reserve(
      taskId: 'task-2',
      estimatedCost: 0.006,
    );
    expect(second.allowed, isFalse);
    expect(second.message, contains('今日全局预算'));
    await budgets.release('task-1');
    final third = await budgets.reserve(taskId: 'task-3', estimatedCost: 0.006);
    expect(third.allowed, isTrue);
    await database.close();
  });

  test('book and chapter budgets block only their own scope', () async {
    final database = await AppDatabase.openInMemory();
    final store = LocalStore(database);
    final budgets = BudgetService(store: store);
    final book = await ImportService(
      store: store,
      paths: database.paths,
    ).importBytes(filename: 'b.txt', bytes: utf8.encode('第一章 测试\n甲乙丙丁。\n'));
    final chapter = (await store.listChapters(book.id)).first;
    await budgets.setLimit(
      scope: BudgetService.scopeBook,
      scopeId: book.id,
      limit: 0.02,
    );
    await budgets.setLimit(
      scope: BudgetService.scopeChapter,
      scopeId: chapter.id,
      limit: 0.01,
    );
    final first = await budgets.reserve(
      taskId: 't1',
      bookId: book.id,
      chapterId: chapter.id,
      estimatedCost: 0.008,
    );
    expect(first.allowed, isTrue);
    final chapterBlocked = await budgets.reserve(
      taskId: 't2',
      bookId: book.id,
      chapterId: chapter.id,
      estimatedCost: 0.005,
    );
    expect(chapterBlocked.allowed, isFalse);
    expect(chapterBlocked.message, contains('本章预算'));

    final otherChapter = await store.createTask(
      type: 'translation',
      title: 'other',
      total: 1,
      bookId: book.id,
      chapterId: null,
    );
    final bookBlocked = await budgets.reserve(
      taskId: otherChapter.id,
      bookId: book.id,
      estimatedCost: 0.015,
    );
    expect(bookBlocked.allowed, isFalse);
    expect(bookBlocked.message, contains('本书预算'));
    await budgets.release('t1');
    await database.close();
  });

  test('running task pauses after actual spend reaches its budget', () async {
    final database = await AppDatabase.openInMemory();
    final store = LocalStore(database);
    final budgets = BudgetService(store: store);
    await budgets.setLimit(scope: BudgetService.scopeTask, limit: 0.005);
    final task = await store.createTask(
      type: 'translation',
      title: 'task',
      total: 10,
    );
    final reserved = await budgets.reserve(
      taskId: task.id,
      estimatedCost: 0.004,
    );
    expect(reserved.allowed, isTrue);
    await store.recordAiUsage(
      taskId: task.id,
      taskType: 'translation',
      inputTokens: 100,
      outputTokens: 50,
      cost: 0.006,
      durationMs: 100,
      status: 'success',
    );
    final message = await budgets.checkDuringTask(task.id);
    expect(message, contains('本任务预算'));
    await budgets.release(task.id);
    final released = await store.db.query(
      'ai_budget_reservations',
      where: 'task_id = ?',
      whereArgs: [task.id],
    );
    expect(released.first['released'], 1);
    await database.close();
  });
}
