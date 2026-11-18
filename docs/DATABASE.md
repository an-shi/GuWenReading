# 数据库设计

最后更新：2026-11-17

## 1. 存储位置

每个设备拥有独立数据库，无中心数据库。默认位置如下，可在设置中更改：

```text
<安装目录>/data/
  library/
    books/<bookId>/original.<ext>
    covers/<bookId>.img
    backups/古文阅读器备份-*.zip
    backups/restore-before-*.db
    tmp/
  database/guwen.db
```

- Windows/Linux 默认使用可执行文件旁的 `data/`；不可写时退回应用支持目录。
- Android/iOS 使用应用私有目录。
- 自定义目录保存在 SharedPreferences 的 `data_root`；启动时优先读取该值。
- 更改目录会关闭数据库，复制 `library/` 与 `database/` 到新位置，成功后清理旧目录中的应用数据并重启应用。
- 数据库使用 SQLite WAL 模式（平台不允许时自动退回）。
- 启动时执行 `PRAGMA foreign_keys = ON`。

## 2. 表结构

### 书籍与文本

- `books`：书名、作者、朝代、分类、简介、标签、格式、原文件路径、封面、哈希、统计、时间。
- `chapters`：书籍、序号、标题、段落数、句子数。
- `paragraphs`：章节、序号、原文、起止偏移。
- `sentences`：段落、章节、书籍、序号、原文、偏移、翻译状态、断句复核标记。

### 翻译

- `translations`：每句最多一条当前译文；来源 `manual`/`ai`、模型、提示词版本、版本号。
- `translation_versions`：译文修改前的历史快照。
- `translation_reviews`：重新翻译候选；`pending`/`accepted`/`rejected`。
- `translation_cache`：提示词与模型组合对应的 AI 响应缓存。

### 阅读状态

- `annotations`：书籍/章节/段落/句子批注、引文、标签、颜色。
- `bookmarks`：书籍、章节、段落、句子、位置比例。
- `reading_progress`：每本书一条，记录章节、段落、句子与位置比例。

### 知识库

- `entities`：标准名、类型、别名、朝代、身份、简介、生卒、字号、职官、审核状态。
- `entity_mentions`：实体在原文中的出现位置与证据。
- `entity_relations`：起点/终点实体、关系类型、说明、状态、置信度。
- `relation_sources`：关系对应的原文证据。
- `historical_events`：事件名、类型、描述、朝代、原始纪年、公元年份、精度、状态。
- `event_participants`：事件参与者。
- `event_sources`：事件原文出处。

### 任务与 AI

- `tasks`：翻译/知识抽取任务、状态、进度、结果、输入/输出 Token、缓存 Token、费用、请求次数。
- `ai_providers`：服务商名称、类型、基础地址、备注、启用状态。
- `ai_models`：服务商、模型标识、显示名、上下文、最大输出、超时、能力、默认翻译/问答/知识抽取、每百万 Token 单价、可选 Tokenizer。
- `ai_usage`：每次 AI 请求的任务、类型、Provider、模型、Token、缓存 Token、费用、耗时、状态、重试次数、估算标记和 Token 来源。
- `translation_sentence_cache`：逐句翻译缓存，Key 包含原文/上下文 Hash、模型、Prompt 版本和策略版本。
- `knowledge_chunk_cache`：知识抽取块级缓存，Key 包含章节、块索引、内容 Hash、模型、Prompt 版本和 Schema 版本。
- `knowledge_extraction_state`：章节级抽取状态，用于内容/模型/Prompt/Schema 未变时跳过 API。
- `prompt_templates`：提示词 key、版本、名称、说明、模板、变量、激活状态。
- `assistant_sessions` / `assistant_messages`：AI 助手会话与消息、引用、claims。
- `app_settings`：本地键值设置。

`historical_events.fingerprint` 用于事件去重，唯一索引只为非空指纹建立。

### 全文检索

```sql
CREATE VIRTUAL TABLE search_fts USING fts5(
  text,
  book_id UNINDEXED,
  chapter_id UNINDEXED,
  sentence_id UNINDEXED,
  doc_type UNINDEXED
);
```

- `doc_type` 为 `original` 或 `translation`。
- 在导入、翻译保存、恢复备份后更新。
- 平台 SQLite 不支持 FTS5 时，`SearchService` 自动使用 `LIKE` 查询。

## 3. 数据完整性

- 外键级联删除书籍、章节、段落、句子与关联翻译/批注。
- `source_hash` 唯一索引防止重复导入。
- `translations.sentence_id` 唯一，保证一句一条当前译文。
- `prompt_templates(key, version)` 唯一。
- 人工译文保护在服务层实现：重新翻译 AI 译文会创建候选，不直接覆盖人工译文。

### 永久删除书籍

书架或书籍详情中的“永久删除”会：

1. 删除 `books` 记录，并级联删除章节、段落、句子、译文、批注、书签和阅读进度。
2. 删除本书产生的 AI 任务和助手会话。
3. 删除本书的全文检索索引。
4. 删除由本书提及、关系或事件产生的孤立人物；仍被其他书引用的人物保留。
5. 删除本书来源的关系和历史事件；仍被其他书引用的保留。
6. 删除原始书籍目录与封面文件。

删除不可撤销。

## 4. 备份与恢复

备份 ZIP：

```text
database/guwen.db
books/...
covers/...
backup.json
```

`backup.json` 记录应用名、版本、创建时间与格式 `guwenreader.backup.v1`。

恢复流程：

1. 解压备份数据库到临时目录。
2. 将当前数据库复制到 `backups/restore-before-*.db`。
3. `ATTACH DATABASE` 备份库，事务内清空并复制业务表。
4. 替换 `books/` 与 `covers/` 文件。
5. 重建 FTS 索引。

## 5. 迁移

数据库仍使用版本 1 的向前兼容策略：

- 启动时执行幂等的 `CREATE TABLE IF NOT EXISTS` 与 `CREATE INDEX IF NOT EXISTS`。
- `AppDatabase._migrate` 通过 `PRAGMA table_info` 检查旧库，按需执行 `ALTER TABLE ADD COLUMN`：
  - `tasks.input_tokens/output_tokens/cache_read_tokens/cache_write_tokens/cost/requests`
  - `ai_models.input_price/output_price/cache_read_price/cache_write_price/is_default_extraction/tokenizer`
  - `historical_events.fingerprint`
  - `ai_usage.token_source`
- 旧记录新列使用 0、空字符串或 NULL 默认值，不删除旧数据。
- 新增缓存表可以重建；翻译结果、实体、关系、事件和史料证据不会被缓存清理影响。
- 备份 ZIP 仍包含正式业务表和书籍文件；`ai_usage` 与缓存表暂不进入备份。
