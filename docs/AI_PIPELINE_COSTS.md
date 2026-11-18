# 章节翻译与知识抽取机制及 AI 成本优化

最后更新：2026-11-17

本文记录当前已实现的章节翻译、知识抽取和 AI 调用计量机制，以及仍然存在的成本优化空间。内容以代码为准。

相关代码：

- `app/lib/core/local/translation_service.dart`
- `app/lib/core/local/knowledge_service.dart`
- `app/lib/core/local/ai_service.dart`
- `app/lib/core/local/prompt_defaults.dart`
- `app/lib/core/local/local_store.dart`
- `app/lib/core/local/schema.dart`
- `app/lib/core/local/app_database.dart`
- `app/lib/features/tasks/tasks_screen.dart`
- `app/lib/features/settings/settings_screen.dart`
- `app/lib/features/reader/reader_screen.dart`
- `app/lib/features/book_detail/book_detail_screen.dart`

## 0. 当前实现摘要

已实现：

1. **统一 AI 调用计量**
   - 每次 AI 请求记录任务、任务类型、Provider、模型、输入/输出 Token、缓存读取/写入 Token、费用、耗时、状态、重试次数和是否估算。
   - 优先读取 Provider 的真实 `usage`；缺失时使用本地保守估算并标记 `is_estimated`。
   - 任务表聚合输入/输出 Token、缓存 Token、费用和请求次数。
   - 任务中心展示总用量、按任务类型/模型统计，以及每个任务的 Token 和费用。

2. **知识抽取联合调用**
   - 原来的“实体、关系、事件各调用一次”改为新的 `knowledge_extract` 联合提示词。
   - 一般章节一次请求完成实体、关系、事件抽取。
   - 超长章节按段落边界和 Token 预算分块，每块一次请求，每块完成立即落库。
   - 使用短句子索引关联证据，不要求模型重复输出 UUID 和完整原文。
   - 章节级 Hash + 模型 + Prompt 版本 + Schema 版本缓存；章节未变时直接复用，不再调用 API。
   - 块级缓存支持部分失败后只重做失败块。
   - 实体优先本地复用；关系按 from/to/type 去重并追加新的史料证据；事件使用指纹去重并合并跨块/跨书证据。

3. **翻译优化**
   - 按模型上下文和最大输出推导批次字符预算，并设置保守安全边界。
   - 请求内部使用短整数索引，不再重复发送句子 UUID。
   - 上下文按句子长度和指代特征动态扩缩，并设置字符上限。
   - 新增逐句翻译缓存，批次边界变化不会导致全部缓存失效。
   - 单句重译默认使用逐句缓存，阅读器另提供“强制重译”绕过缓存。
   - 保留批次级提示词缓存作为第二层缓存。

4. **任务防重复与恢复**
   - 同一章节已有运行中的翻译/抽取任务时直接返回已有任务。
   - 任务支持取消；暂停任务在再次点击任务入口时可恢复。
   - 翻译成功的句子、知识抽取成功的块都会缓存，恢复时不会重复计费。
   - 单次任务费用达到设置上限时自动暂停。

5. **模型路由基础**
   - 支持默认翻译模型、默认问答模型、默认知识抽取模型。
   - 未设置默认知识抽取模型时回退到默认问答模型，兼容旧配置。
   - 模型可配置输入、输出、缓存读取、缓存写入单价（每百万 Token，币种由用户自行统一）。

尚未实现（见第 7 节）：

- Provider 原生 Prompt Caching 和 Batch API 的显式支持。
- 精确 Tokenizer；当前对没有 usage 的响应使用估算。
- 单章节、单本书级别的独立预算（目前是单次任务预算）。
- 自动在应用重启后无人工点击恢复任务。
- AI 参与的多候选实体消歧。
- 供应商连接测试调用的用量统计。
- 按实体/关系/事件分别路由不同模型；当前联合抽取使用一个“知识抽取模型”。

## 1. 翻译调用链

```text
ReaderScreen / BookDetailScreen
        │
        ▼
TranslationService.startChapterTranslation
        │
        ├─ 同一章节已有 queued/running 任务？直接返回
        ├─ 同一章节有 paused 任务？恢复执行
        └─ 创建 tasks(type=translation)
                │
                ▼
TranslationService._run
        │
        ├─ 选择目标句子：跳过人工译文；普通重译跳过已有 AI 译文
        ├─ 逐句查 translation_sentence_cache
        │     ├─ 命中：本地写回译文 + FTS，不调用 API
        │     └─ 未命中：进入待翻译列表
        ├─ 按模型预算动态分批
        ├─ 查 translation_cache（批次级完整提示词缓存）
        │     ├─ 命中：使用缓存 JSON
        │     └─ 未命中：AiJsonClient.chatJson（记录 usage/费用）
        ├─ 按短索引解析 translations/items
        ├─ 成功的句子写入 translations、逐句缓存和 FTS
        ├─ 失败句标记 failed，不重发已成功句
        └─ 更新任务进度；达到任务预算时暂停
```

### 1.1 目标句子

- 人工译文永远不会被 AI 覆盖。
- `retranslate=false`：只处理没有译文或上次失败的句子。
- `retranslate=true`：处理所有非人工译文，但逐句缓存仍可复用。

### 1.2 批次预算

`_batchCharBudget` 使用：

```text
输出边界 = max(400, maxOutputTokens × 0.75)
输入边界 = max(600, contextWindow - maxOutputTokens - 1200)
批次预算 = max(400, min(6000, 输出边界, 输入边界))
```

这是保守的字符预算，中文按接近“1 字符 ≈ 1 token”处理。它没有接入各 Provider 的精确 tokenizer，但能避免固定 2200 字导致小上下文模型超限或输出截断。

### 1.3 翻译短 ID

请求内：

```json
{"id": 1, "text": "原文"}
```

模型返回：

```json
{"id": 1, "text": "译文"}
```

应用只在本地维护 `1..N → sentence UUID` 映射；数据库中的 UUID 不变。解析同时兼容 `id/i` 与 `text/t`，也兼容旧提示词。

### 1.4 上下文策略

- 默认只带前后各一句。
- 当前句较长（≥80 字）或以“其、此、是、彼、故、然、則、而、曰、蓋、夫”等开头时，才增加相邻段落的一小段。
- 前后文合计限制在约 700 字符。
- 固定规则在前、变化的原文在后，便于 Provider 自动前缀缓存。

### 1.5 逐句缓存

表：`translation_sentence_cache`。

缓存 Key：

```text
sha256(
  原文 Hash |
  上下文 Hash |
  模型显示名 |
  Prompt 版本 |
  缓存策略版本
)
```

策略版本当前为 2。逐句缓存解决了“批次边界改变导致整批缓存失效”的问题。

单句重译：

- 默认 `useCache=true`：命中则直接写回，不调用 API。
- 阅读器“强制重译”按钮调用 `useCache=false`：绕过缓存，产生新请求。

### 1.6 批次缓存

表：`translation_cache`。

Key：

```text
sha256(模型 label | Prompt 版本 | 缓存策略版本 | 完整渲染后的 Prompt)
```

批次缓存和逐句缓存同时存在：逐句命中优先，批次缓存作为完整提示词精确复用的兜底。

### 1.7 失败与重试

- 模型缺失某句译文：只将该句标记 failed。
- JSON/网络异常：该批未成功句子标记 failed，任务继续下一批。
- 下一次任务只选择没有译文/失败的句子，不重复发送已成功句。
- 失败句不会被原文冒充为译文。
- 目前同一任务内不做无限自动重试；重试由用户再次创建任务触发，成功结果都会落库/缓存。

### 1.8 取消与恢复

- 每个批次开始前检查任务状态；取消后停止继续请求。
- 已成功的句子和逐句缓存保留。
- 暂停任务再次点击翻译入口会恢复；已翻译句子不会再次请求。

## 2. 知识抽取调用链

```text
BookDetailScreen 章节操作
        │
        ▼
KnowledgeService.startExtraction
        │
        ├─ 同章节已有 queued/running/paused 任务：返回或恢复
        └─ 创建 tasks(type=knowledge_extraction)
                │
                ▼
KnowledgeService._runExtraction
        │
        ├─ 解析“知识抽取模型”，未配置时回退“问答模型”
        ├─ 计算章节 Hash
        ├─ 章节级状态命中（内容/模型/Prompt/Schema 都一致）
        │     └─ 直接复用，不调用 API
        ├─ 按段落边界 + Token 预算分块
        └─ 对每个块：
              ├─ 查 knowledge_chunk_cache
              ├─ 命中：直接应用缓存结果
              ├─ 未命中：knowledge_extract 联合抽取一次
              ├─ 缓存块结果
              ├─ 在事务中应用实体/关系/事件
              └─ 更新任务进度；达到预算时暂停
```

### 2.1 联合抽取

新默认提示词：`knowledge_extract`。

一次请求同时返回：

```json
{
  "entities": [
    {"id": 1, "name": "张三", "type": "person", "aliases": [], "evidence": [1]}
  ],
  "relations": [
    {"from": 1, "to": 2, "type": "君臣关系", "evidence": [1]}
  ],
  "events": [
    {
      "name": "某事件",
      "type": "war",
      "time": null,
      "year": null,
      "precision": "unknown",
      "participants": [1, 2],
      "evidence": [2]
    }
  ]
}
```

规则：

- `id` 是本块内的实体短索引。
- `evidence` 是本块内的句子短索引，应用根据索引读取真实原文。
- 关系、事件必须有证据；没有有效证据的关系/事件不会写入。
- 不要求模型输出人物介绍、原文摘录或冗长解释。
- 古籍原文 UUID 不进入 Prompt，也不要求模型返回。

### 2.2 分块

`_buildChunks`：

- 默认按段落边界累积。
- 单段超过预算时按句子切分。
- Token 预算：

```text
inputBound = max(900, contextWindow - maxOutputTokens - 1200)
outputBound = max(900, maxOutputTokens × 2)
blockBudget = max(900, min(5000, inputBound, outputBound))
```

- 当前估算器：CJK 字符按 1 token，其他字符按 4 字符/token。
- 同一章节的块索引稳定；内容 Hash 变化后只重新处理变化的块。

### 2.3 章节级跳过

表：`knowledge_extraction_state`。

保存：

- 章节内容 Hash
- 模型显示名
- Prompt 版本
- Schema 版本
- 状态

内容、模型、Prompt、Schema 全部一致且状态为 completed 时，重复点击不再调用 API。模型或提示词变化不会删除已有知识数据，只会重新抽取并依靠实体/关系/事件去重合并。

### 2.4 块级缓存与断点

表：`knowledge_chunk_cache`。

Key：

```text
chapter_id + chunk_index + content_hash + model_label +
prompt_version + schema_version
```

- 每块成功后立即缓存并落库。
- 某块失败时任务可以 partial 结束；下次执行只重新请求失败的块。
- 块结果在数据库事务中应用，单块失败不会留下半块数据。
- 当前没有应用重启后自动继续执行；用户再次点击抽取会复用缓存。

### 2.5 实体复用

- 新实体优先按 `canonical_name` 精确匹配。
- 再按 `aliases` 字段中的完整别名匹配。
- 命中已有实体时只补充缺失别名/朝代，不覆盖已有正式介绍。
- 没有多候选 AI 消歧，避免为消歧额外付费；遇到无法确定的同名人物按本地精确/别名结果处理。

### 2.6 关系去重

- 以 `from_entity_id + to_entity_id + relation_type` 去重。
- 已存在关系时继续追加新的 `relation_sources`，不会丢弃新史料证据。
- 关系仍默认 `inferred`，等待人工审核。

### 2.7 事件去重

`historical_events.fingerprint` + 唯一索引。

指纹组成：

```text
规范化事件名
+ 事件类型
+ year / time
+ 排序后的参与者名称
```

如果时间、参与者都缺失，则把首条证据原文 Hash 纳入指纹，避免同名但无时间的事件被错误合并。

- 相同指纹：复用事件，追加新的 `event_sources` 和参与者。
- 不同指纹：保留为不同事件，支持“同名不同事”。
- 旧数据 fingerprint 为空；仅在时间/类型/年份匹配时做有限回退匹配，避免按名称粗暴去重。
- 跨章节/跨书的同一事件会保留全部证据来源。

### 2.8 事务边界

- 实体、关系、事件在单个块内的事务中写入。
- 块与块之间不是一个大事务；前面成功的块会保留。
- 失败块不写缓存；再次执行时只补失败块。
- 任务状态：`queued / running / completed / partial / failed / cancelled / paused`。

## 3. 统一计量与费用

### 3.1 数据表

`ai_usage`：

```text
id, task_id, task_type, provider_id, provider_name,
model_id, model_name,
input_tokens, output_tokens,
cache_read_tokens, cache_write_tokens,
total_tokens, cost, duration_ms,
status, retry_count, is_estimated, error, created_at
```

`tasks` 新增聚合列：

```text
input_tokens, output_tokens,
cache_read_tokens, cache_write_tokens,
cost, requests
```

### 3.2 usage 归一化

- OpenAI / OpenAI 兼容：`prompt_tokens`、`completion_tokens`、`prompt_tokens_details.cached_tokens`
- Anthropic：`input_tokens`、`output_tokens`、`cache_read_input_tokens`、`cache_creation_input_tokens`
- Ollama：`prompt_eval_count`、`eval_count`
- 无 usage：使用 `estimateTokens`，并设置 `is_estimated=1`

### 3.3 费用

模型表新增：

```text
input_price, output_price,
cache_read_price, cache_write_price
```

单位为“每百万 Token”，币种由用户自行统一。缓存单价为 0 时按输入单价兜底估算；所有单价为 0 时费用为 0，并在 UI 提示“未配置模型单价”。

计算：

```text
费用 =
  input_tokens × input_price
  + output_tokens × output_price
  + cache_read_tokens × cache_read_price
  + cache_write_tokens × cache_write_price
  ÷ 1,000,000
```

### 3.4 UI

任务中心顶部“AI 用量”：

- 累计调用次数
- 累计输入/输出/缓存 Token
- 累计费用
- 按任务类型统计
- 按模型统计

每个任务卡：

- 请求次数
- 输入/输出 Token
- 缓存读取 Token
- 费用
- 错误和结果计数

设置 → AI 模型：

- 模型编辑增加四个单价字段。
- 成本控制增加“单次任务费用上限”。
- 达到上限时任务暂停，错误提示包含当前费用和上限。

## 4. 任务去重、取消与恢复

- 翻译任务按 `chapter_id + type=translation` 查重。
- 知识抽取任务按 `chapter_id + type=knowledge_extraction` 查重。
- 运行中任务直接返回已有任务，不创建新任务。
- 暂停任务再次启动时恢复，已成功句子/块不重复计费。
- 取消任务在批次/块边界生效；当前已发出的请求可能仍会计费并记录 usage。
- 任务状态和实际执行状态以 `tasks` 表为准。

## 5. 数据库变化

新增表：

- `ai_usage`
- `translation_sentence_cache`
- `knowledge_chunk_cache`
- `knowledge_extraction_state`

新增/变更列：

- `tasks.input_tokens/output_tokens/cache_read_tokens/cache_write_tokens/cost/requests`
- `ai_models.input_price/output_price/cache_read_price/cache_write_price/is_default_extraction`
- `historical_events.fingerprint` + 唯一索引

兼容策略：

- `AppDatabase._migrate` 使用 `PRAGMA table_info` 检查旧库，存在则跳过 `ALTER TABLE`。
- 新表使用 `CREATE TABLE IF NOT EXISTS`。
- 旧书籍、译文、实体、关系、事件数据不删除。
- 新缓存表可重建；正式翻译/知识数据不会因缓存清理而丢失。
- 旧任务没有 Token 字段，显示为 0。

## 6. 测试与实测

自动化测试：

- `app/test/ai_pipeline_test.dart`
  - 本地 Mock OpenAI 兼容服务
  - 翻译请求与任务用量
  - 逐句缓存命中
  - 单句缓存与强制重译
  - 任务去重
  - 长章节分块联合抽取
  - 实体复用、关系/事件落库
  - 事件跨块证据合并
  - 重复抽取章节跳过 API
  - 按类型/模型用量汇总
  - 预算超限暂停

- 原有测试继续通过：导入、翻译保护、批注/书签/进度、备份恢复、桌面/移动应用壳。
- 当前共 11 项测试通过。

原有真实数据量参考（用于估算）：

- 3,337 章
- 1,416,431 句
- 28,165,934 原文字符
- 单章最大 40,000 字符
- 旧方案整书知识抽取约 10,011 次请求（3 次/章）
- 新方案正常章节约 3,337 次请求，长章节按块增加；重复抽取可跳过
- 旧翻译按 2200 字分批约 14,520 次请求；新批次预算随模型输出能力变化

## 7. 已知限制与后续优化

### 7.1 精确 Tokenizer

当前只在 Provider 返回 usage 时使用真实 Token；分块预算和无 usage 的计量使用保守估算。后续可按模型配置 tokenizer 或接入 Provider token count 接口。

### 7.2 Prompt Caching

固定规则已经在 Prompt 前部、动态原文在后部，但应用没有显式发送 Provider 的缓存控制字段。部分 Provider 会自动做前缀缓存；是否命中取决于其规则。后续可对支持的 Provider 增加缓存标记并记录缓存读写 Token。

### 7.3 Batch API

尚未实现。整本书翻译/抽取非常适合异步 Batch API，可在不改变现有实时流程的前提下作为可选任务类型。

### 7.4 预算粒度

当前只有“单次任务费用上限”。尚未提供单章节、单本书预算；可在设置中增加多级预算，并在启动前根据历史 token 估算费用。

### 7.5 自动恢复

应用重启后不会自动重新启动 running 任务；用户再次点击会利用句子/块缓存继续。后续可在任务启动时检测未完成任务并提示恢复。

### 7.6 实体消歧

当前只做本地精确/别名匹配，没有多候选 AI 消歧。若未来加入，应只在候选冲突时调用，并记录额外费用。

### 7.7 事件指纹

指纹是启发式：同名、同时间、同参与者可能合并；不同史料的不同表述可能保持为不同事件。当前策略偏保守，避免错误合并，但可能保留少量重复事件。

### 7.8 备份

`ai_usage` 和抽取/翻译缓存暂未纳入备份 ZIP。正式译文、实体、关系、事件仍在数据库备份中；缓存可在新设备重建。

### 7.9 模型路由

支持翻译、问答、知识抽取三个默认模型；尚未做到实体/关系/事件分别使用不同模型。由于当前是联合抽取，一个知识抽取模型即可覆盖整个任务。

### 7.10 并发与重试

单个任务内部串行处理批次/块，没有无限并发；但不同章节的任务目前可以同时启动，尚未加入全局任务队列/并发上限。网络失败不会自动重试，由用户再次启动任务，已成功的结果会从缓存复用，不会重复发送。

## 8. 成本优化检查清单

- [x] 记录真实 usage，缺失时标记估算
- [x] 任务级 Token/费用聚合
- [x] 任务去重
- [x] 翻译逐句缓存
- [x] 翻译短 ID
- [x] 翻译批次按模型预算
- [x] 知识抽取联合调用
- [x] 知识章节缓存/块缓存
- [x] 长章节分块和失败块重试
- [x] 实体复用、关系证据合并
- [x] 事件指纹去重
- [x] 单次任务预算暂停
- [x] 知识抽取模型/问答模型回退
- [ ] 精确 tokenizer 和 token count API
- [ ] Provider 原生 Prompt Caching
- [ ] Batch API
- [ ] 单章节/单本书预算
- [ ] 应用重启自动恢复任务
- [ ] 多候选实体 AI 消歧
- [ ] 备份 AI 用量与缓存
