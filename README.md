# 古文阅读器

古文阅读器是一个**本地优先、单机独立运行**的古籍阅读与研究工具。桌面端与移动端使用同一套 Flutter 代码和本地 Dart 核心，不需要安装、启动或连接任何后端服务。

导入古籍后，应用会在本机完成章节识别、段落构建、逐句切分、全文检索索引、AI 翻译、知识抽取与备份。原文始终保留，译文按句子精确关联，AI 抽取的人物、关系与事件保留原文证据并默认处于待审核状态。

## 核心特性

- **完全独立运行**：桌面端与 APP 各自拥有本地 SQLite 数据库，不依赖服务器、账户或网络服务。
- **古籍导入**：TXT、EPUB、DOCX、文本型 PDF；原文件与提取文本均保存在本机。
- **精确阅读**：章节、段落、句子偏移；原文/译文交替、原文优先、逐句对照、桌面双栏。
- **AI 翻译**：OpenAI 兼容接口或 Ollama；逐句翻译、分批上下文、缓存、人工修订保护、候选审核、版本历史。
- **知识研究**：人物/地点/职官/机构/典籍抽取，人物关系图谱，历史时间线，原文证据与审核状态。
- **全文检索**：SQLite FTS5；不支持 FTS5 的平台自动回退到 LIKE 检索。
- **AI 阅读助手**：结合当前章节、本地检索结果与知识库回答，区分原文明示、推断、分析与证据不足。
- **本地备份**：一键创建完整 ZIP 备份，支持导出、恢复与恢复前数据库副本。
- **全中文界面**：暖色纸张阅读风格，品牌名“古文阅读器”。

## 项目结构

```text
app/                统一的 Flutter 桌面/移动应用
  lib/
    core/local/     本地核心：SQLite、文档解析、AI、翻译、知识、检索、备份
    data/           数据模型与本地仓库
    features/       书架、详情、阅读器、检索、知识、图谱、时间线、任务、设置
    app/            应用壳、主题与响应式导航
  test/             本地核心与应用测试
docs/               架构、数据库、本地核心、提示词、构建与测试文档
```

## 运行

### 桌面端（Windows）

```powershell
cd app
flutter pub get
flutter run -d windows
```

要求：

- Flutter 3.47+、Visual Studio（Windows Desktop C++ 工具链）。
- **Windows 必须开启“开发者模式”**，Flutter 插件构建需要符号链接支持。
- 首次构建会编译 SQLite/PDFium 等原生依赖，耗时较长。

### Android

```powershell
cd app
flutter pub get
flutter run -d <android-device>
```

构建调试 APK：

```powershell
flutter build apk --debug
```

### iOS / macOS

需要 macOS + Xcode。工程已包含 `ios/` 平台配置，未在 Windows 上构建验证。

## AI 配置

打开“我的 → AI 模型”：

1. 添加服务商：可选择 OpenAI、DeepSeek、通义千问、豆包、Kimi、智谱、硅基流动、Gemini、Claude、OpenRouter、Ollama 等预设。
2. 填写 API Key 后点击“获取模型”，勾选要使用的模型；应用会保存上下文长度与多模态能力。
3. 分别指定默认翻译模型与默认问答模型。

接口密钥保存在系统安全存储中；不会写入日志、导出文件或界面明文。

## 数据与备份

默认数据目录：

- Windows/Linux：安装目录下自动创建的 `data/`
- Android/iOS/macOS：应用私有支持目录

目录包含：

```text
library/books/          原始书籍文件
library/covers/         封面
library/backups/        备份 ZIP 与恢复前数据库副本
library/tmp/            解析与备份临时文件
database/guwen.db       SQLite 数据库
```

可在“设置 → 数据备份 → 更改数据目录”调整位置，迁移完成后自动重启。旧版 AppData 数据会在首次启动时复制到新目录。

备份文件名为 `古文阅读器备份-YYYYMMDD-HHMMSS.zip`。恢复会覆盖当前数据库与书籍文件，并在 `backups/` 中保留恢复前数据库副本。

## 功能边界

- 扫描版 PDF 的 OCR 未实现；没有可提取文字的 PDF 会被明确拒绝。
- 桌面端与移动端不自动同步。需要在设备间迁移时，使用备份导出/恢复。
- 关系与事件的人工创建/编辑尚未在 UI 中全部开放，AI 抽取结果可审核。
- Windows 安装包需要在开启开发者模式后执行 `flutter build windows`；Android release 签名需自行配置。
- 真实第三方 AI 服务需要在“AI 模型”中填写你自己的密钥；项目不包含隐藏 API Key 或遥测。

## 测试

```powershell
cd app
flutter analyze
flutter test
```

测试覆盖 TXT/EPUB/DOCX 导入、章节/句子构建、全文检索、人工译文保护、候选审核、批注/书签/进度、备份创建与恢复。

## 文档

- [架构](docs/ARCHITECTURE.md)
- [数据库](docs/DATABASE.md)
- [本地核心](docs/LOCAL_CORE.md)
- [AI 提示词](docs/AI_PROMPTS.md)
- [构建与发布](docs/BUILD.md)
- [开发计划](docs/DEVELOPMENT_PLAN.md)
- [测试报告](docs/TEST_REPORT.md)
- [应用说明](app/README.md)
