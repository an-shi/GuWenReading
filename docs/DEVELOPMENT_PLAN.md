# 开发计划与完成情况

最后更新：2026-11-16

状态图例：✅ 完成并验证 · 🟡 已实现但验证/范围有限 · ⛔ 未实现

## 阶段 1：项目基础设施 ✅

- Monorepo：`backend/`、`desktop/frontend/`、`desktop/src-tauri/`、`mobile/`。
- FastAPI app factory、lifespan、CORS、统一 envelope、全局异常处理、请求 ID、访问日志。
- SQLAlchemy 2 异步模型、SQLite pragma、FTS5 初始化、Alembic 初始迁移。
- 配置系统：Embedded/Server 模式、数据目录、环境变量。
- API 契约与健康/能力接口。
- 结构化日志 + 敏感信息过滤。
- 桌面端桥接：Axios API 客户端、Vite 开发代理/直连、WebSocket 任务订阅。
- Tauri 2 壳、图标、sidecar 启动逻辑已编写；**本机无 Cargo，未编译**。

## 阶段 2：书籍管理与文档解析 ✅（手动章节调整除外）

- TXT（UTF-8/GB18030/Big5/UTF-16 检测）、EPUB、DOCX、文本型 PDF。
- 元数据识别、章节识别、段落构建、句子切分、字符偏移。
- SHA-256 去重、托管存储、原文件完整保留、提取文本保存。
- 重解析（有译文时阻止；force 归档旧译文）。
- 书籍列表/搜索/排序/标签/分类/封面/进度。
- 桌面书架、书籍详情、导入对话框；移动书架、导入、详情、下载整本。
- 测试覆盖：编码、四类解析器、偏移一致性、重复导入、重解析保护。

⛔ 手动拖拽/编辑章节边界尚未提供；当前通过重解析与源文件修正。
⛔ 扫描版 PDF OCR 未实现，明确报错。

## 阶段 3：AI 模型管理与翻译 ✅（部分高级能力未验证）

- Provider/Model CRUD、连接测试、默认翻译/问答模型。
- KeyVault：Windows DPAPI / Fernet 环境密钥 / 受保护本地密钥。
- Prompt 文件 + 数据库版本、激活/回滚、变量渲染。
- 章节/段落/句子翻译任务；动态分批；上下文；缓存；重试；取消；恢复。
- 人工译文保护、候选审核、版本历史。
- 任务持久化、WebSocket 进度、HTTP 轮询。
- 测试覆盖：完整翻译、手动修订保护、重翻译候选、接受候选、缓存命中、失败记录、密钥不泄露。

🟡 模型的 `max_concurrency` 已存储但当前任务 worker 默认串行执行；未实现多模型并发调度。
🟡 `quality_review` Prompt 已提供，但 UI 尚未接入一键审校。

## 阶段 4：Windows 阅读器 ✅（章节内搜索除外）

- 原文/译文双栏、单滚动容器的段落/句子精确对齐。
- 句级点击联动、段落/句子高亮、状态占位。
- 章节目录、上一章/下一章、翻译进度、自动翻译开关。
- 字体/行距/主题、原文/译文/对照模式。
- 句子详情、人工修订、重翻译、候选审核、版本历史。
- 书签、批注、按设备阅读进度恢复。
- AI 助手抽屉、引用/claims/本地史料。
- 全局全文搜索并可定位句子。

⛔ 阅读器内章节搜索未做（全局搜索可用）。
🟡 滚动位置保存使用滚动比例 + 当前段落，不是逐像素位置。

## 阶段 5：Flutter 移动端阅读器 🟡

- 书架、书籍详情、导入、TOC、下载整本、离线缓存。
- 四种阅读模式：交替、原文优先、原文/译文独立切换、逐句。
- 模式切换保持当前段落索引；长章节使用 ScrollablePositionedList 虚拟化。
- 句级详情、AI 解释、批注创建/删除、书签添加、阅读进度本地优先。
- 翻译状态、共享翻译任务轮询、取消。
- 手机直连 OpenAI 兼容翻译（独立模式）+ 混合模式。
- 知识库人物/事件浏览与资料页；AI 助手。
- `flutter analyze` 无问题；单元测试通过；debug APK 构建成功。

🟡 批注仅支持创建/删除，不支持编辑。
🟡 移动端直连只实现 OpenAI 兼容 Chat Completions，不支持 Ollama 原生 API。
🟡 移动端下载的书是提取后的章节内容与译文，不同步原始二进制文件。
🟡 同步只覆盖批注/书签/进度的本地待推送队列；未实现完整 pull + 冲突 UI。

## 阶段 6：AI 阅读助手 ✅

- 当前书籍/章节/段落/句子上下文。
- 本地 FTS/实体/事件检索作为依据。
- 回答含 citations、claims 分类、本地 sources。
- 会话持久化、历史消息。
- 桌面抽屉与移动底部弹层。
- 引用验证：存在 sentence_id 时校验引文是否为原文子串。

## 阶段 7：人物知识库与关系图谱 🟡

- 实体抽取（人物/地点/职官/机构/典籍等）、别名、Mention 证据、待审状态。
- 同名/多别名歧义：仅在唯一匹配时自动复用；否则创建待审实体。
- 手动实体合并、状态更新。
- 关系抽取（explicit/inferred）、来源引用、审核 API。
- 桌面 G6 图谱、中心人物、朝代/关系类型筛选、层级、点击详情、证据。
- 跨书籍共享 Library 级知识库。

🟡 关系人工创建/编辑仅后端 API，桌面/移动 UI 未接入。
🟡 实体字段人工编辑仅前端知识库状态/合并，完整表单未接入。

## 阶段 8：历史事件时间线 🟡

- 事件抽取、参与者、证据、状态。
- 年号/公元/区间换算；干支保留不猜测；歧义保持 unknown。
- 桌面 ECharts 时间线、类型/朝代筛选、事件详情、来源。
- 移动事件列表/详情。
- 所有事件保留原始纪年 `time_raw`。

🟡 年号表覆盖常见汉至清王朝，非穷尽；未知年号会保留原文并标记 unknown。
🟡 时间精度暂以年为主要展示粒度；月/日精度保留标签但不做精确日期计算。
🟡 事件人工创建/编辑 UI 未接入（API 已实现）。

## 阶段 9：多设备同步 🟡

- Server 模式 JWT、首用户注册、设备注册/列表/删除。
- SyncOperation 日志、push/pull、游标、冲突记录、接受客户端/服务端。
- 翻译人工保护、阅读进度按设备独立。
- 备份创建/列表/下载 + 停服恢复脚本。
- 桌面设置页显示连接/设备/同步状态/备份。
- 移动端本地优先批注/书签/进度与待推送队列。

🟡 桌面端使用后端数据库直连，不需要独立 push/pull 客户端；Server 模式下它本身是直接客户端。
🟡 移动端尚未实现完整 sync pull 与冲突解决 UI；章节内容通过下载接口缓存。
🟡 书籍二进制文件不做自动同步，移动端按章节下载内容。

## 阶段 10：测试、优化与发布 🟡

- 后端 48 项自动化测试通过。
- 桌面前端 `vue-tsc` + Vite 构建通过；真实浏览器 UI 冒烟通过。
- Flutter analyze 无问题、5 项测试通过（含离线缓存/本地状态/直连译文合并）、Android debug APK 构建成功。
- 全中文界面清理：桌面端与移动端用户可见的装饰性英文标题、分区标签和枚举展示已统一为中文；品牌名、模型标识、文件格式、接口地址与提示词模板中的结构化字段名按技术契约保留。
- 产品名称统一为古文阅读器：桌面/移动端品牌、窗口标题、应用名、后端系统信息、FastAPI 文档标题、备份元数据与构建配置均已同步；Tauri 标识、PyInstaller sidecar、npm/Cargo/Flutter 包名、Android applicationId 与 iOS bundle ID 一并更新。
- 新默认数据目录为 `%APPDATA%\古文阅读器`；备份前缀为“古文阅读器备份”，备份格式与移动端数据库文件名保留 ASCII 技术标识。
- 备份创建/恢复脚本已实测。
- 使用本地 mock OpenAI 服务验证翻译、翻译缓存、人物/关系/事件抽取、AI 助手、图谱、时间线。

⛔ Windows Tauri 安装包未构建（无 Cargo）。
⛔ iOS 构建/签名未验证（Windows 环境）。
⛔ 真实第三方 AI 服务未测试（无 API Key）。
⛔ 10 万句/大文件压力基准未运行。
⛔ 扫描版 PDF OCR 未实现。

## 重要文件索引

- 后端入口：`backend/app/main.py`
- 书籍导入：`backend/app/modules/book_manager/service.py`
- 解析器：`backend/app/modules/document_parser/`
- 断句：`backend/app/modules/text_processor/splitter.py`
- 翻译：`backend/app/modules/translation/service.py`
- 任务：`backend/app/modules/task_manager/runner.py`
- 知识抽取：`backend/app/modules/knowledge/extraction.py`
- 检索：`backend/app/modules/search/service.py`
- 同步：`backend/app/modules/sync/service.py`
- 桌面：`desktop/frontend/src/`
- 移动：`mobile/lib/`

## 下一阶段优先级

1. 生成 Tauri Windows 安装包并验证 sidecar 生命周期。
2. 在 macOS/Xcode 构建 iOS release，配置签名。
3. 移动端完整 pull sync + 冲突 UI + 原始文件按需下载。
4. 关系/事件人工创建编辑 UI 与 alias 编辑。
5. 章节内搜索、精确滚动位置、手动章节边界编辑。
6. FTS5/大文件/10 万句性能基准与索引优化。
7. 真实 Provider 兼容性矩阵测试（DeepSeek/OpenAI/Ollama 等）。
8. 以 Alembic 统一 Embedded 启动升级流程。
