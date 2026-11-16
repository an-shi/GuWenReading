# 古文阅读器架构

## 1. 总览

```
┌──────────────────────┐     HTTP / WebSocket      ┌──────────────────────┐
│ Vue 3 + Tauri 2      │ ────────────────────────▶ │ FastAPI (embedded /  │
│ Windows 桌面端        │ ◀──────────────────────── │ server)              │
└──────────────────────┘     /api/v1, /ws/tasks      │ SQLAlchemy 2         │
                                                      │ SQLite / PostgreSQL  │
┌──────────────────────┐     HTTP（可选 Server）     │ Prompt / AI / FTS5   │
│ Flutter Android/iOS  │ ────────────────────────▶ │                      │
│ 本地 SQLite 缓存      │ ◀──────────────────────── │                      │
└──────────────────────┘                            └──────────┬───────────┘
                                                               │ OpenAI-compatible
                                                               ▼
                                                    ┌──────────────────────┐
                                                    │ Provider adapter     │
                                                    │ OpenAI / Ollama / …  │
                                                    └──────────────────────┘
```

Windows 与移动端都是完整客户端。桌面端可以内置 Python 后端（Embedded），也可连接 Server 模式；移动端必须连接一个后端完成文档解析与共享翻译，但会把已下载内容保存到本地，离线阅读不依赖网络。

## 2. 后端分层

```
app/
  api/v1/               路由、请求模型、统一 envelope
  core/                 配置、日志、安全、错误、路径
  database/             session、ORM 模型、FTS5
  ai/                   Provider 适配层、Prompt 版本、JSON 修复
  modules/
    book_manager/       导入、托管存储、书架查询、重解析
    document_parser/    TXT/EPUB/DOCX/PDF 提取与章节识别
    text_processor/     规范化、繁简转换、古文断句
    translation/        上下文、分批、缓存、人工保护、审核
    task_manager/       持久任务、取消、恢复、WebSocket 事件
    knowledge/          人物/关系/事件抽取、纪年、图谱、时间线
    search/             FTS5 与 LIKE 回退
    assistant/          基于当前文本与本地史料的问答
    sync/               设备、增量操作、冲突
    system/             健康、能力、备份
```

所有业务逻辑位于后端；客户端只负责展示和交互。API 契约见 `docs/API.md` 与 `/docs`。

## 3. 原文与派生文本

导入时：

1. 计算文件 SHA-256，拒绝重复。
2. 原文件复制到 `data/books/<book_id>/source/<filename>`，**从不修改原文件**。
3. 解析器输出章节 → 段落结构。
4. 构建统一 extracted text；章节、段落、句子都保存 `start_offset` / `end_offset`。
5. 原文段落与句子写入数据库；翻译、繁简转换等仅作为派生数据存在。

句子切分采用保守策略：

- 句末标点、省略号与后置引号归入同一句。
- 超长且无标点的段落保留整段并标记 `needs_review`，不强行分割。
- 极长逗号句只在接近中间处切分，并降低置信度。
- 每句保存原文偏移，测试会验证 `extracted[start:end] == original_text`。

## 4. 翻译流水线

```
Chapter translation request
  → persistent Task
  → select untranslated sentences (skip existing translations)
  → paragraph-aware batches sized by model context
  → prompt version + context hash + cache lookup
  → Provider chat completion (JSON)
  → per-sentence save
       existing manual? → TranslationReview candidate, keep current
       existing AI?     → archive TranslationVersion, replace
       no translation?  → create Translation
  → update sentence/chapter/book counts
  → FTS translation index
  → task progress over WebSocket
```

- 任务在服务端持久化；取消在批次边界生效；失败句子记录状态，可重新发起。
- Cache key = 原文 hash + 上下文 hash + provider/model + prompt version + 参数。
- 人工修订的译文不会被自动翻译覆盖；重新翻译会生成待审候选，由用户接受或拒绝。
- 任务每批立即提交，因此断点恢复只补未完成句子。

## 5. 任务与实时事件

`TaskRunner` 单/多 worker 从数据库任务队列取任务，支持：

- `queued / running / completed / partial / failed / cancelled`
- 取消请求、启动恢复（把中断的 running 改回 queued）
- 任务进度与结果持久化
- WebSocket `/ws/tasks` 推送 `task_started / task_progress / task_completed / task_failed / task_cancelled`
- HTTP 轮询作为备用，移动端始终可用轮询

## 6. 知识库

AI 抽取只产生待审核数据：

- `HistoricalEntity.status = pending`（人工确认后 confirmed）
- `EntityRelation.status = explicit | inferred | confirmed | rejected`
- `HistoricalEvent.status = extracted | confirmed | rejected`
- 每条关系/事件保留 `RelationSource` / `EventSource` 到具体句子
- 同名实体不会仅凭名字自动合并；自动匹配只接受唯一别名/同名结果，模糊情况创建待审实体，用户可手动合并

纪年处理：

- 保留 `time_raw`、年号、干支原文
- 有可靠年号/公元锚点才换算
- 年号歧义（同名年号）或缺锚点的干支 → `unknown`，不猜测
- 时间线将“有明确年份”和“时间未详”分开

## 7. 检索

SQLite FTS5 使用字符级中文索引：写入时在 CJK 字符间插入空格，查询时按短语匹配，解决 unicode61 不切分中文的问题。片段返回后清理索引空格。

非 SQLite / FTS5 不可用时自动回退到 LIKE 查询；这保证服务可用，但性能与排序弱于 FTS5。启动时若索引为空而有历史数据，会自动回填原文与译文索引。

## 8. 同步

- 所有可同步实体使用 `version` / `updated_at` / `deleted_at`。
- 客户端先写本地，再 push；pull 使用全局递增 `sync_operations.seq`。
- 阅读进度以 `(book_id, device_id)` 唯一，设备之间绝不互相覆盖。
- 冲突规则：
  - 服务端人工译文 > 客户端 AI 译文
  - 双方人工译文且 base_version 过期、内容不同 → conflict，等待用户选择
  - 其他实体采用版本检查 + 时间戳 LWW；冲突记录在 `sync_operations`
- 冲突解决 API 提供 accept_server / accept_client（强制重放客户端内容）。
- 书籍原文/章节内容通过 manifest + chapter download 传输，而不是放入操作日志。

## 9. 前端

### Windows

- 单滚动容器的两列网格实现原文/译文精确对齐，句子 id 对应同一行；不是通过滚动条比例估算。
- 点击原文句子与译文句子联动高亮；译文缺失显示状态占位。
- 任务 WebSocket 实时刷新；失败和人工审核有明确入口。
- G6 图谱与 ECharts 时间线；节点/关系状态区分已确认/推断。
- 设置中管理 Provider、Model、Prompt、阅读偏好、Server 登录与备份。

### Flutter

- 本地 SQLite：书籍/章节内容缓存、批注、书签、阅读进度、移动端直连译文。
- 四种阅读模式：交替、原文优先、原文/译文切换、逐句对照。模式切换按当前段落索引恢复位置。
- `ScrollablePositionedList` 虚拟化长章节；不加载整本书。
- 共享翻译通过后端任务；直连模式在手机侧调用 OpenAI 兼容接口；混合模式优先后端、离线时直连。
- 离线：已缓存章节可阅读；批注/书签写本地并标记 dirty，联网后推送；阅读进度本地优先。
- 后台限制：翻译任务在后端继续；APP 轮询任务或刷新章节。

## 10. 安全

- `KeyVault`：Windows DPAPI；带 `GUWEN_SECRET_KEY` 时使用 Fernet；否则受保护的本地密钥文件。
- API Key 写入加密字段，响应只返回 hint 与 has_key。
- 日志过滤敏感模式。
- Server 模式默认强制 JWT 认证；首个账户注册后，后续账户需要已认证用户创建。
- 备份含敏感史料与译文，需用户自行保管。

## 11. 已知边界

- OCR、向量检索、WebDAV/云盘同步未实现。
- Tauri 原生壳未在当前环境编译验证。
- iOS 构建/签名无法在 Windows 验证。
- 移动端独立 AI 只实现 OpenAI 兼容 Chat Completions（不包含 Ollama 原生协议）。
- 移动端知识库页面依赖后端在线；阅读缓存离线可用。
