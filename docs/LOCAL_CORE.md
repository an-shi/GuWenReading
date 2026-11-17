# 本地核心接口

最后更新：2026-11-17

应用没有 HTTP API。UI 通过 Riverpod 调用本地仓库与服务，所有方法在当前进程内执行。

## 1. 数据库与服务

`core/providers.dart` 提供：

```dart
appDatabaseProvider       // AppDatabase
localStoreProvider        // LocalStore（SQLite 读写）
aiSettingsProvider        // AI 服务商/模型/提示词/密钥
aiClientProvider          // OpenAI 兼容 / Anthropic / Ollama 请求
importServiceProvider     // 导入与解析
translationServiceProvider
knowledgeServiceProvider
searchServiceProvider
assistantServiceProvider
backupServiceProvider
localApiProvider          // 面向 UI 的本地门面
```

## 2. LocalApi

`LocalApi` 是 UI 的统一入口，保留原移动端仓库习惯的方法名：

| 方法 | 说明 |
| --- | --- |
| `books({query})` / `book(id)` | 书架与书籍详情 |
| `chapters(bookId)` / `chapterContent(chapterId)` | 章节列表与阅读内容 |
| `translationStatus(chapterId)` | 翻译统计 |
| `translateChapter(chapterId)` | 创建本地翻译任务 |
| `task(id)` / `tasks()` / `cancelTask(id)` | 本地任务 |
| `annotations` / `bookmarks` / `progress` | 阅读状态 |
| `importBook(...)` | 本地导入 |
| `entities` / `entity` / `events` / `event` | 知识库 |
| `assistant(...)` | 本地 AI 助手 |
| `search(...)` | FTS5/LIKE 检索 |

## 3. ImportService

```dart
Future<Book> importBytes({
  required String filename,
  required Uint8List bytes,
  String? title,
  String? author,
  String? dynasty,
  String? category,
  String? tags,
})
```

- 支持 `.txt`、`.epub`、`.docx`、`.pdf`。
- 计算 SHA-256 去重。
- 保存原文件与封面。
- 生成章节、段落、句子与 FTS 索引。

## 4. TranslationService

- `startChapterTranslation(chapterId, retranslate)`：创建任务并异步执行。
- `retranslateSentence(sentenceId)`：重译单句。
- `saveManual(sentenceId, text)`：保存人工译文。
- `resolveReview(reviewId, accept)`：采用或驳回候选。

## 5. KnowledgeService

- `startExtraction(chapterId)`：实体 → 关系 → 事件。
- `listEntities` / `entity` / `setEntityStatus` / `mergeEntities`。
- `listEvents` / `event` / `setEventStatus`。
- `graph` / 时间线查询。

## 6. SearchService

```dart
Future<LocalSearchResults> search(
  String query, {
  String scope = 'all', // all | original | translation
  String? bookId,
})
```

返回原文/译文命中、人物与事件；所有结果来自本机数据库。

## 7. AssistantService

```dart
Future<AssistantAnswer> ask({
  required String question,
  String? bookId,
  String? chapterId,
  String? paragraphId,
  String? sentenceId,
  String? sessionId,
})
```

构建当前章节上下文与本地检索资料，调用默认问答模型，校验引用并保存会话。

## 8. BackupService

- `createBackup()`：生成 ZIP。
- `listBackups()` / `deleteBackup(path)`。
- `restoreBackup(path)`：事务复制数据并恢复文件。

## 9. 错误约定

本地核心抛出 `ApiException`（历史命名保留）或具体领域异常：

- `DocumentParseException`：文件格式/编码/无文本。
- `AiNotConfiguredException`：未配置模型。
- `AiRequestException`：AI 请求或 JSON 解析失败。
- `TranslationException` / `KnowledgeException`：业务错误。
- `BackupException`：备份格式/恢复错误。

UI 统一以 SnackBar 或错误页展示，不静默吞掉核心错误。
