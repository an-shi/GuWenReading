# AI Prompt 管理

## 1. 原则

- Prompt 不硬编码在业务逻辑中：全部放在 `backend/app/resources/prompts/<key>/v<version>.md`。
- 每个 Prompt 有独立 key 与递增版本；数据库 `prompt_templates` 保存版本内容。
- 首次启动时，若数据库中不存在某 key，则导入内置文件的最新版本。
- 后续修改通过 API 创建新版本；旧版本保留，可随时启用。
- 每条译文保存 `prompt_version`；知识/事件记录的来源元数据也记录 Prompt 版本（事件 `metadata_json.prompt_version`）。
- 翻译缓存 key 包含 Prompt 版本，因此切换 Prompt 不会错误复用旧缓存。

## 2. 文件格式

```markdown
---
key: translation
version: 1
name: 文言文翻译（Balanced）
variables: book_title, author, dynasty, chapter_title, context_before, context_after, items_json
description: 将文言文句子准确、通顺地译为现代汉语。
---
Prompt 正文，使用 {{variable}} 占位符。
```

文件位置：`backend/app/resources/prompts/<目录>/v<版本>.md`。启动时扫描全部 `*/v*.md`。

## 3. 内置 Prompt

| key | 用途 | 主要变量 |
| --- | --- | --- |
| `translation` | 文言文 → 现代汉语（Balanced） | book_title, author, dynasty, chapter_title, context_before/after, items_json |
| `assistant` | 阅读助手问答，JSON 回答 + citations/claims | book_title, author, chapter_title, context, knowledge_context, history, question |
| `sentence_explain` | 句子释义 | original, translation, context, question |
| `word_glossary` | 词语释义 | word, sentence |
| `historical_background` | 历史背景解释 | context, question |
| `entity_extract` | 人物/地名/职官等实体抽取 | paragraphs_json |
| `relation_extract` | 人物关系抽取 | entities_json, paragraphs_json |
| `event_extract` | 历史事件抽取 | paragraphs_json |
| `conflict_analysis` | 不同史料冲突比较 | subject, sources_json |
| `quality_review` | 译文质量检查 | original, translation, context |

## 4. 翻译 JSON 契约

模型必须只返回：

```json
{
  "translations": [
    { "id": "sentence uuid", "text": "现代汉语译文", "uncertain": false, "note": "" }
  ]
}
```

处理规则：

- 严格校验 id；未返回的句子标记失败，不猜测内容。
- 代码围栏会被剥离；非法 JSON 会触发一次“只输出合法 JSON”的修复请求。
- 修复仍失败 → 批次失败，任务记录失败句子；可重新发起任务。
- 翻译结果去除首尾空白；人工译文永不被覆盖。
- 请求中的 items 是批量句子；批大小由模型上下文、最大输出与配置动态计算，不会一次发送整章。

## 5. 上下文与缓存

- Prompt 包含章节标题、书籍/作者/朝代、前后文与本批句子。
- 缓存 key 包含：原文 hash、段落上下文 hash、Provider、Model、Prompt 版本、温度等参数。
- 上下文变化会改变 key，避免“同一句在不同语境复用错误译文”。
- 缓存只复用 AI 译文；人工修订不会进入自动缓存覆盖流程。

## 6. API

```http
GET  /api/v1/ai/prompts
GET  /api/v1/ai/prompts/translation
POST /api/v1/ai/prompts/translation/versions
{
  "name": "翻译 v2",
  "template": "... {{items_json}} ...",
  "variables": ["items_json"],
  "description": "可选"
}
POST /api/v1/ai/prompts/translation/activate/1
```

创建新版本会自动停用旧版本；启用旧版本会保留全部历史。

## 7. 安全与质量

- Prompt 中不得加入 API Key、用户隐私或服务器密钥。
- Provider 原始响应只写入数据库的译文/候选/错误摘要；日志会过滤敏感模式。
- Prompt 要求模型区分原文明示、合理推断、AI 分析与证据不足，避免把推断当史实。
- 质量审校 Prompt 已提供；当前 UI 尚未接入“一键质量检查”，可通过 API/服务层扩展。
