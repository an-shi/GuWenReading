import 'dart:convert';

import 'package:flutter/material.dart';

import '../../data/models.dart';

/// Shows the shared book metadata editor.
///
/// Returns the column values to pass to [LocalStore.updateBook], or `null` if
/// the user cancelled or left the title empty.
Future<Map<String, Object?>?> showBookEditDialog(
  BuildContext context,
  Book book,
) async {
  final title = TextEditingController(text: book.title);
  final author = TextEditingController(text: book.author ?? '');
  final dynasty = TextEditingController(text: book.dynasty ?? '');
  final category = TextEditingController(text: book.category ?? '');
  final tags = TextEditingController(text: book.tags.join('、'));
  final description = TextEditingController(text: book.description ?? '');
  String? error;
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('编辑书籍信息'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '书名'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: author,
                        decoration: const InputDecoration(labelText: '作者'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: dynasty,
                        decoration: const InputDecoration(labelText: '朝代'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: category,
                        decoration: const InputDecoration(labelText: '分类'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: tags,
                        decoration: const InputDecoration(
                          labelText: '标签（顿号分隔）',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: description,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: '简介'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty) {
                setDialogState(() => error = '书名不能为空');
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  final values = saved == true
      ? <String, Object?>{
          'title': title.text.trim(),
          'author': author.text.trim().isEmpty ? null : author.text.trim(),
          'dynasty': dynasty.text.trim().isEmpty ? null : dynasty.text.trim(),
          'category': category.text.trim().isEmpty
              ? null
              : category.text.trim(),
          'description': description.text.trim().isEmpty
              ? null
              : description.text.trim(),
          'tags': jsonEncode(
            tags.text
                .split(RegExp(r'[、,，]'))
                .map((tag) => tag.trim())
                .where((tag) => tag.isNotEmpty)
                .toList(),
          ),
        }
      : null;
  title.dispose();
  author.dispose();
  dynasty.dispose();
  category.dispose();
  tags.dispose();
  description.dispose();
  return values;
}

/// Confirms a permanent book deletion with a clear warning.
Future<bool> confirmBookDeletion(BuildContext context, Book book) async {
  final theme = Theme.of(context);
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('永久删除《${book.title}》？'),
          content: const Text(
            '书籍原文、译文、批注、书签、阅读进度、AI 任务，以及由本书提取的人物、关系、历史事件等关联数据都会一并删除。\n\n'
            '原始文件和封面也会删除，无法撤销。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('永久删除'),
            ),
          ],
        ),
      ) ??
      false;
}

/// Runs [action] behind a modal progress dialog and always closes it.
Future<void> runWithProgressDialog(
  BuildContext context,
  String message,
  Future<void> Function() action,
) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
  try {
    await action();
  } finally {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
