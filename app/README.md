# 古文阅读器应用

统一的 Flutter 桌面/移动应用。桌面端与 APP 使用同一套本地核心，不依赖任何独立后端。

## 目录

```text
lib/
  core/local/     SQLite、文档解析、AI 客户端、翻译、知识、检索、备份
  data/           共享数据模型与本地仓库
  features/       书架、详情、阅读器、检索、知识库、图谱、时间线、任务、设置
  app/            应用壳、主题、响应式导航
  domain/         阅读模式与领域枚举
test/             本地核心与阅读模式测试
```

## 本地核心

- `AppDatabase`：跨平台 SQLite（桌面使用 `sqflite_common_ffi`，移动端使用 `sqflite`）。
- `ImportService`：TXT/EPUB/DOCX/文本型 PDF 解析、章节/段落/句子切分与 FTS 索引。
- `TranslationService`：本地 AI 翻译、缓存、人工译文保护、候选审核、版本历史。
- `KnowledgeService`：实体、关系、事件抽取与审核；图谱与时间线查询。
- `SearchService`：FTS5 全文检索与 LIKE 回退。
- `AssistantService`：本地知识上下文 + AI 问答。
- `BackupService`：ZIP 备份、导出、恢复与恢复前副本。

## 运行

```powershell
flutter pub get
flutter run -d windows
```

Windows 需要开启开发者模式（Flutter 插件符号链接）。Android/iOS 使用 `flutter run -d <device>`。

## 测试

```powershell
flutter analyze
flutter test
```

## 说明

- 没有后端进程、HTTP API、服务器地址或账户系统。
- 数据只保存在本机；跨设备迁移使用备份导出/恢复。
- 扫描版 PDF 的 OCR 未实现。
