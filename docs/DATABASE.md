# 数据库设计

数据库使用 SQLAlchemy 2.x Declarative 模型，默认 SQLite（`sqlite+aiosqlite`），Server 模式可用 PostgreSQL（`postgresql+asyncpg`）。

- 主键：字符串 UUID（36 字符），由 `IdMixin` 自动生成。
- 时间：数据库内保存 naive UTC，API 序列化为带 `Z` 的 ISO 字符串。
- 可同步实体：继承 `SyncMixin`，包含 `version`、`updated_at`、`deleted_at`。
- 删除：业务数据默认软删除；原文/章节在重新解析时可硬删除。
- 事务：服务层显式 commit；失败自动 rollback；任务每批保存。

## 1. 表分组

### 书籍与原文

| 表 | 作用 | 关键字段/约束 |
| --- | --- | --- |
| `books` | 书籍元数据与托管文件 | `content_hash` unique；`original_path` / `extracted_path` 相对数据目录；`deleted_at` 软删除 |
| `chapters` | 章节结构 | `(book_id, ordinal)` unique；`start_offset/end_offset` 指向 extracted text |
| `paragraphs` | 段落 | `(chapter_id, ordinal)` unique；原文 + normalized_text + 偏移 |
| `sentences` | 句子 | `(paragraph_id, ordinal)` unique；原文 + 偏移 + `translation_state` |

原始文件路径指向 `data/books/<id>/source/`，提取文本在 `data/books/<id>/extracted.txt`。任何翻译都不会写回这些文件或原文列。

### 译文与任务

| 表 | 作用 |
| --- | --- |
| `translations` | 每句当前译文；`sentence_id` unique；`origin = ai/manual` |
| `translation_versions` | 被替换/人工修订前的历史版本（不依赖 sentence 外键，重解析后仍保留） |
| `translation_reviews` | 人工译文被 AI 重新翻译时的候选，待 accept/reject |
| `translation_cache` | 原文 hash + 上下文 hash + 模型 + Prompt 版本 + 参数的缓存 |
| `tasks` | 持久化后台任务；status/progress/payload/result/cancel_requested |
| `prompt_templates` | Prompt 版本库；`(key, version)` unique |

### AI 配置

- `ai_providers`：名称、类型、Base URL、加密 API Key、hint、headers、启用状态。
- `ai_models`：Provider 外键、模型 ID、上下文、最大输出、超时、并发、JSON/流式能力、默认翻译/问答标记。
- `assistant_sessions` / `assistant_messages`：AI 阅读助手对话与 citations。
- `glossary`：预留的历史词汇表。

### 阅读状态

- `annotations`、`bookmarks`：软删除与版本字段。
- `reading_progress`：`(book_id, device_id)` unique；**设备之间彼此独立**。
- `devices`：设备注册/最后在线；fingerprint unique。
- `users`：仅 Server 模式使用；PBKDF2-SHA256 密码哈希。

### 知识库

- `historical_entities`：标准名、字、号、谥号、庙号、别名、朝代、身份、生卒、审核状态。
- `entity_mentions`：实体在某句中的出现；可人工确认来源。
- `entity_relations`：source/target/type/status；`explicit / inferred / confirmed / rejected`。
- `relation_sources`：关系对应的书籍、章节、段落、句子与原文引文。
- `historical_events`：名称、类型、原始纪年、年号/干支、标准化年份、精度、审核状态。
- `event_participants`、`event_sources`：参与者与史料证据。

### 同步

- `sync_operations`：自增 `seq`，记录每次 push 的操作、版本、状态、冲突快照。`applied / conflict / resolved_server` 参与 pull。
- `sync_cursor`：每个设备最后拉取的 seq。

### FTS5

`search_fts` 为 FTS5 虚拟表：

```sql
CREATE VIRTUAL TABLE search_fts USING fts5(
  doc_type UNINDEXED, doc_id UNINDEXED, book_id UNINDEXED, chapter_id UNINDEXED,
  title, body, tokenize='unicode61 remove_diacritics 2'
);
```

写入时把 CJK 字符用空格分隔，以支持中文短语检索；`doc_type` 为 `original` 或 `translation`，`doc_id` 为 sentence id。启动时若索引为空而存在历史数据，会自动回填。

## 2. 关键关系

```
books 1─n chapters 1─n paragraphs 1─n sentences 1─1 translations
                                             └── translation_versions
                                             └── translation_reviews
books 1─n annotations / bookmarks
books 1─n reading_progress (per device)
historical_entities n─n historical_entities via entity_relations
entity_relations 1─n relation_sources ─ sentence
historical_events 1─n event_sources ─ sentence
historical_events n─n historical_entities via event_participants
```

## 3. 索引与约束

- 书籍：`content_hash` unique，标题/分类/状态索引。
- 章节/段落/句子：`(parent_id, ordinal)` 唯一索引，按书/章的查询索引。
- 译文：`sentence_id` unique，`chapter_id` 索引。
- 事件：年份索引、类型/朝代索引。
- 实体：名称、类型、朝代索引。
- 阅读进度：`(book_id, device_id)` unique。
- 所有子表对书籍/章节/段落有 `ON DELETE CASCADE`；历史译文版本不挂 sentence 外键，避免重解析时丢失版本。

## 4. 迁移

Alembic 配置位于 `backend/alembic.ini`，初始化迁移：

```
backend/alembic/versions/5d3b8b424a4c_initial_schema.py
```

```powershell
cd backend
$env:GUWEN_DATA_DIR = "D:\古文阅读器-data"
..\.venv\Scripts\python.exe -m alembic upgrade head
```

- 迁移包含全部 30 张业务表、索引、外键，以及在 SQLite 上创建 `search_fts`。
- Server/PostgreSQL 部署建议设置 `GUWEN_AUTO_CREATE_SCHEMA=false` 并只通过 Alembic 升级。
- Embedded 模式当前启动时使用 `create_all` 作为首次建库；已有数据库升级应使用 Alembic。生产发版前应改为启动时统一执行迁移（见 DEVELOPMENT_PLAN 遗留事项）。

## 5. 备份

备份 ZIP 包含：

- `database/guwen.db`（使用 SQLite online backup API 生成一致性快照）
- `books/`（原始文件 + extracted.txt）
- `covers/`
- `backup.json`（版本、创建时间、格式）

恢复使用 `scripts/restore_backup.py`，必须在后端停止时运行；恢复前会自动保存当前数据库和书籍目录到 `data/backups/pre-restore-*`。
