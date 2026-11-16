# 古文阅读器 API

Base path: `/api/v1`。交互式 OpenAPI：`/docs`。

## 1. 统一响应

成功：

```json
{ "success": true, "data": {}, "message": "success" }
```

失败：

```json
{
  "success": false,
  "data": null,
  "message": "Book not found",
  "error": { "code": "NOT_FOUND", "message": "Book not found", "details": null }
}
```

HTTP 状态码与错误码同时存在。常见错误码：

`VALIDATION_ERROR`、`NOT_FOUND`、`CONFLICT`、`DUPLICATE_BOOK`、`UNSUPPORTED_FORMAT`、`PARSE_ERROR`、`FILE_TOO_LARGE`、`TRANSLATION_NOT_CONFIGURED`、`PROVIDER_ERROR`、`AI_INVALID_RESPONSE`、`AUTH_REQUIRED`、`AUTH_INVALID`、`FORBIDDEN`、`SYNC_DISABLED`、`MANUAL_TRANSLATION_PROTECTED`、`REPARSE_BLOCKED`。

分页响应统一为：

```json
{ "items": [], "total": 0, "page": 1, "page_size": 20 }
```

## 2. 认证

- Embedded 模式默认免登录。
- Server 模式默认强制 Bearer JWT。
- 首个账户可公开注册；已有用户后，新账户需已认证用户创建。

```http
POST /api/v1/auth/register
POST /api/v1/auth/login
GET  /api/v1/auth/me
Authorization: Bearer <token>
```

设备：

```http
GET    /api/v1/devices
POST   /api/v1/devices/register
DELETE /api/v1/devices/{device_id}
```

## 3. 书籍与章节

```http
GET    /api/v1/books?q=&category=&tag=&sort=recent|imported|title|author&page=1&page_size=24
POST   /api/v1/books/import            multipart: file, title?, author?, dynasty?, category?, description?, tags?
GET    /api/v1/books/{book_id}
PUT    /api/v1/books/{book_id}
DELETE /api/v1/books/{book_id}?permanent=false
POST   /api/v1/books/{book_id}/reparse?force=false
GET    /api/v1/books/{book_id}/cover
GET    /api/v1/books/{book_id}/original
GET    /api/v1/books/{book_id}/manifest
GET    /api/v1/books/{book_id}/chapters
GET    /api/v1/chapters/{chapter_id}
GET    /api/v1/chapters/{chapter_id}/paragraphs
GET    /api/v1/chapters/{chapter_id}/content
GET    /api/v1/chapters/{chapter_id}/translation-status
GET    /api/v1/chapters/{chapter_id}/download
```

章节内容返回段落、句子、精确字符偏移、当前译文、翻译状态、待审候选、前后章节 ID。`/download` 为完整离线包 JSON。

## 4. 翻译

```http
POST /api/v1/translations/chapter/{chapter_id}       { model_id?, retranslate?, only_failed? }
POST /api/v1/translations/paragraph/{paragraph_id}   { model_id?, retranslate? }
POST /api/v1/translations/sentence/{sentence_id}     { model_id?, retranslate? }
POST /api/v1/translations/retranslate/{translation_id}
GET  /api/v1/translations/sentence/{sentence_id}
GET  /api/v1/translations/{translation_id}
PUT  /api/v1/translations/{translation_id}           { text, note? }
POST /api/v1/translations/sentence/{sentence_id}/manual { text }
GET  /api/v1/translations/{translation_id}/versions
GET  /api/v1/translations/reviews?status=pending
POST /api/v1/translations/reviews/{review_id}/resolve { action: accept|reject, text? }
POST /api/v1/translations/{translation_id}/review    { action, text? }
```

翻译接口返回 **202 + Task**。客户端通过任务/WS 观察进度，最终重新拉取章节内容。

## 5. 任务与 WebSocket

```http
GET  /api/v1/tasks?status=&type=&book_id=&page=&page_size=
GET  /api/v1/tasks/{task_id}
GET  /api/v1/tasks/{task_id}/progress
POST /api/v1/tasks/{task_id}/cancel
```

WebSocket：`ws://127.0.0.1:8765/ws/tasks`（Server 模式需 `?token=`）

事件：

```json
{ "type": "task_started|task_progress|task_completed|task_failed|task_cancelled", "task": { ... } }
```

另有 `connected` 与 `heartbeat`。

## 6. AI 配置与 Prompt

```http
GET/POST        /api/v1/ai/providers
PUT/DELETE      /api/v1/ai/providers/{provider_id}
POST            /api/v1/ai/providers/{provider_id}/test   { model_name? }
GET/POST        /api/v1/ai/models
PUT/DELETE      /api/v1/ai/models/{model_id}
GET             /api/v1/ai/prompts
GET             /api/v1/ai/prompts/{key}
POST            /api/v1/ai/prompts/{key}/versions
POST            /api/v1/ai/prompts/{key}/activate/{version}
```

Provider 响应只包含 `api_key_hint` 与 `has_api_key`，绝不返回明文/密文 Key。

## 7. 知识库 / 检索 / 助手

```http
GET  /api/v1/entities?q=&kind=&dynasty=&status=&page=
GET  /api/v1/entities/search?q=
GET  /api/v1/entities/{entity_id}
GET  /api/v1/entities/{entity_id}/mentions
POST /api/v1/entities
PUT  /api/v1/entities/{entity_id}
POST /api/v1/entities/{entity_id}/merge { source_entity_ids: [] }

GET  /api/v1/relations?entity_id=&relation_type=&include_pending=
POST /api/v1/relations
PUT  /api/v1/relations/{relation_id}/review?status=confirmed

GET  /api/v1/graph?center_id=&depth=2&dynasty=&relation_type=&book_id=&include_pending=
GET  /api/v1/events?q=&event_type=&dynasty=&status=&page=
GET  /api/v1/events/{event_id}
POST /api/v1/events
PUT  /api/v1/events/{event_id}
PUT  /api/v1/events/{event_id}/review?status=confirmed
GET  /api/v1/timeline?year_from=&year_to=&event_type=&dynasty=&include_extracted=

POST /api/v1/knowledge/extract { chapter_id, model_id?, extract_entities, extract_relations, extract_events }

GET  /api/v1/search?q=&scope=all|original|translation&book_id=&limit=

POST /api/v1/assistant/chat { question, book_id?, chapter_id?, paragraph_id?, sentence_id?, session_id?, model_id? }
GET  /api/v1/assistant/sessions
GET  /api/v1/assistant/sessions/{session_id}
```

检索结果包含 `sentence_id`、书/章、原文、译文和 FTS 摘要（`[[高亮]]`）。实体/事件结果保留审核状态。

## 8. 阅读状态

```http
GET /api/v1/reading-progress?book_id=&device_id=
GET /api/v1/reading-progress/{book_id}?device_id=local
PUT /api/v1/reading-progress
GET/POST/PUT/DELETE /api/v1/annotations...
GET/POST/DELETE     /api/v1/bookmarks...
```

阅读进度以 `(book_id, device_id)` 区分，绝不跨设备覆盖。

## 9. 同步

```http
GET  /api/v1/sync/status?device_id=
POST /api/v1/sync/push
GET  /api/v1/sync/pull?device_id=&after=0&limit=200
GET  /api/v1/sync/conflicts
POST /api/v1/sync/conflicts/{seq}/resolve?action=accept_client|accept_server
```

Push body:

```json
{
  "device_id": "phone-...",
  "operations": [
    {
      "entity_type": "translation|annotation|bookmark|reading_progress|entity|relation|event|book",
      "entity_id": "...",
      "operation": "upsert|delete",
      "base_version": 0,
      "version": 1,
      "updated_at": "2026-11-16T00:00:00Z",
      "data": {}
    }
  ]
}
```

Pull 返回自增 `seq` 大于 after 的 applied 操作与 `next_cursor`。冲突不会被应用，需显式解决。

## 10. 系统与备份

```http
GET  /api/v1/system/health
GET  /api/v1/system/info
POST /api/v1/system/backup             (需要认证；仅 SQLite)
GET  /api/v1/system/backups            (需要认证)
GET  /api/v1/system/backups/{filename} (需要认证)
```

备份 ZIP 含数据库、书籍和封面。恢复需停止服务并运行 `scripts/restore_backup.py`。
