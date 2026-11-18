import '../../data/models.dart';
import 'ai_scheduler.dart';
import 'knowledge_service.dart';
import 'local_store.dart';
import 'translation_service.dart';

/// Recovers tasks left behind by a previous process.
///
/// A task is only interrupted when its lease owner differs from the current
/// process, so tasks started in this run are never touched. Persisted
/// sentences, chunks and caches are reused when the task resumes.
class TaskRecoveryService {
  TaskRecoveryService({
    required this.store,
    required this.translation,
    required this.knowledge,
  });

  final LocalStore store;
  final TranslationService translation;
  final KnowledgeService knowledge;

  Future<List<TaskInfo>> recoverOnStartup({bool autoResume = true}) async {
    final tasks = await store.recoverStaleTasks(appInstanceId);
    if (!autoResume) return tasks;
    for (final task in tasks) {
      await _resume(task);
    }
    return tasks;
  }

  Future<void> resume(TaskInfo task) => _resume(task);

  Future<void> _resume(TaskInfo task) async {
    switch (task.type) {
      case 'translation':
        await translation.resumeTask(task.id);
      case 'knowledge_extraction':
        await knowledge.resumeTask(task.id);
      default:
        // Batch and auxiliary task types are resumed by their own module when
        // implemented; leave the interrupted record visible for the user.
        break;
    }
  }
}
