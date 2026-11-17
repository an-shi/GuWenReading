# 开发计划与完成情况

最后更新：2026-11-16

状态图例：✅ 完成并验证 · 🟡 已实现但验证/范围有限 · ⛔ 未实现

## 目标

古文阅读器是**单机独立**应用：桌面端与移动端共享 Flutter/Dart 本地核心，不依赖独立后端、服务器进程或远程数据库。

## 阶段 1：统一 Flutter 应用 ✅

- `app/` 统一 Flutter 工程，包含 Android、iOS、Windows。
- 响应式应用壳：宽屏 NavigationRail，窄屏底部导航。
- 暖色纸张主题、宋体标题、统一中文化界面。
- 响应式页面：书架、详情、阅读器、检索、知识、图谱、时间线、任务、设置。

## 阶段 2：本地核心与数据库 ✅

- SQLite Schema：书籍、章节、段落、句子、译文、版本、候选、缓存、批注、书签、进度。
- 知识库、关系、事件、出处、任务、AI 服务商/模型、提示词、助手会话。
- FTS5 索引与 LIKE 回退。
- 跨平台数据库工厂：桌面 `sqflite_common_ffi`，移动端 `sqflite`。
- 备份/恢复：VACUUM 快照、ZIP、ATTACH 事务复制、恢复前副本。

## 阶段 3：文档导入与文本处理 ✅

- TXT：UTF-8/UTF-16/GB18030/Big5 解码。
- EPUB：container/OPF/spine/XHTML，元数据与封面。
- DOCX：WordprocessingML 段落与文本。
- PDF：PDFium 文字提取；扫描版无文字时明确拒绝。
- 章节识别、段落合并、逐句切分、偏移与断句置信度。
- SHA-256 去重、原文件落盘、索引建立。

## 阶段 4：AI 与翻译 ✅（真实服务待验证）

- OpenAI 兼容 / OpenAI / Ollama 客户端。
- API Key 系统安全存储。
- 提示词版本管理、启用/回滚。
- 章节分批翻译、上下文、缓存、任务进度、取消。
- 人工译文保护、单句重译、候选审核、版本历史。
- 自动翻译开关。

## 阶段 5：阅读器 ✅

- 原文/译文交替、原文优先、切换、逐句、桌面双栏。
- 段落/句子点击、句子详情、批注、书签、阅读进度。
- 章节目录、上一章/下一章、章节内搜索。
- 字体、行距、主题、阅读模式设置。
- 句子人工译文、重新翻译、候选采用/驳回、版本历史、AI 解释。

## 阶段 6：知识库、图谱与时间线 ✅

- 实体/关系/事件抽取与原文证据。
- 人物、地点、职官、机构、典籍分类。
- 人物关系图谱（GraphView）。
- 历史时间线（有年份/时间待考）。
- 实体与关系审核、事件确认/驳回。
- 实体合并接口（UI 可继续完善）。

## 阶段 7：检索与 AI 助手 ✅

- 原文/译文/人物/事件统一检索。
- FTS5 高亮、书籍/章节定位。
- 当前章节 + 本地检索上下文回答。
- 引用校验、claims 分类、会话保存。

## 阶段 8：备份与数据迁移 ✅

- 完整 ZIP 备份。
- 备份列表、导出、删除。
- 恢复并重建 FTS。
- 恢复前数据库副本。

## 阶段 9：验证 🟡

- `flutter analyze` 无问题。
- `flutter test` 10 项通过：TXT/EPUB/DOCX 导入、检索、人工译文保护、候选审核、批注/书签/进度、备份创建与恢复、移动端/桌面端应用壳启动。
- Android debug APK 构建成功。
- Windows 构建被开发者模式阻塞，未运行验证。
- Android 模拟器未能启动，未做设备 UI 冒烟。
- 真实第三方 AI 服务未测试（无 API Key）。

## 仍未完成

- ⛔ 扫描版 PDF OCR。
- ⛔ Windows 图形界面运行验证（需开启开发者模式）。
- ⛔ Android/iOS 真机 UI 冒烟。
- ⛔ 真实 AI Provider 端到端测试。
- 🟡 关系/事件人工创建与完整编辑 UI。
- 🟡 自动跨设备同步（当前通过备份迁移）。
- 🟡 章节内搜索仅覆盖当前章节，跨书检索通过全局检索。

## 重要文件

- 应用入口：`app/lib/main.dart`
- 本地数据库：`app/lib/core/local/app_database.dart`
- Schema：`app/lib/core/local/schema.dart`
- 导入：`app/lib/core/local/import_service.dart`
- 文档解析：`app/lib/core/local/document_parser.dart`
- 翻译：`app/lib/core/local/translation_service.dart`
- 知识：`app/lib/core/local/knowledge_service.dart`
- 检索：`app/lib/core/local/search_service.dart`
- 助手：`app/lib/core/local/assistant_service.dart`
- 备份：`app/lib/core/local/backup_service.dart`
- UI：`app/lib/features/`

## 下一阶段优先级

1. 在开启开发者模式的 Windows 环境构建并做完整 UI 冒烟。
2. Android 模拟器/真机验证导入、阅读、翻译、备份。
3. 真实 AI 服务兼容性测试（OpenAI 兼容、Ollama）。
4. 补全关系/事件人工创建编辑 UI 与实体合并 UI。
5. 大文件/10 万句性能优化与索引基准。
6. iOS 构建与签名。
