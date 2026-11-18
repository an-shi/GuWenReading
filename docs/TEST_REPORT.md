# 测试报告

日期：2026-11-17

## 1. 自动化测试

### 静态检查

```powershell
cd app
flutter analyze
```

结果：`No issues found!`

### 单元/集成测试

```powershell
cd app
flutter test
```

结果：`36 tests passed`

覆盖：

- TXT 导入：元数据、章节、段落、句子、FTS 检索。
- 人工译文保护与 AI 重译候选审核。
- 批注、书签、阅读进度本地持久化。
- EPUB 导入：OPF/spine/XHTML、书名/作者、章节文本。
- DOCX 导入：WordprocessingML 段落文本。
- 备份创建、列表与恢复；恢复后数据状态一致。
- 阅读模式映射与章节内容序列化。
- 移动端/桌面端应用壳启动：底部导航与 NavigationRail。
- AI 联合抽取、Token/费用计量、翻译短 ID 与批次缓存、逐句翻译缓存、任务去重、长章节分块、事件证据合并、章节重复抽取跳过、单次任务预算暂停（Mock OpenAI 兼容服务）。
- Tokenizer Adapter：模型系列识别、配置覆盖、本地 Tokenizer 注册、CJK/Latin 估算和 Token 来源标记。
- 连接测试计量：成功和失败都写入 `ai_usage`，按 `connection_test` 单独统计。
- 完整/轻量备份：完整备份保留缓存和 `ai_usage`，轻量备份清空缓存；恢复保留正式数据与用量；过新版本备份被拒绝。
- 全局调度：全局/Provider/模型/任务并发、429 重试与计量、不可重试错误直接失败。
- 三级预算：每日全局、书籍、章节、任务预算；并发预留、释放和运行中预算检查。
- 任务心跳与恢复：跨进程遗留 `running` 任务标记为 `interrupted`，恢复时复用已保存结果。
- 本地质量检查：翻译缺失/空值/未翻译/长度异常，知识实体 ID、关系端点、证据和年份。
- 知识可信度与来源：`knowledge_type`、来源任务/模型/Prompt/Schema 版本。
- 实体消歧：多候选 AI 选择、低置信度独立建实体、消歧缓存。
- 人工审核：确认/撤销、合并去重、拆分提及并写审计。
- Prompt/Schema 版本：新增、启用、缓存/用量版本记录。
- Provider 故障切换：可恢复错误切换备用模型，401 等配置错误不切换。
- Anthropic Prompt Caching：请求包含 `cache_control`，缓存写入 Token 计入费用。
- 成本分析：缓存节省、成功率、平均耗时、章节/实体/关系/事件平均费用。

### Android 构建

```powershell
cd app
flutter build apk --debug
```

结果：APK 构建成功。

- 包名：`com.guwenreading.app`
- 应用标签：古文阅读器
- 包含 `libpdfium.so` / `libpdfrx_pdfium_gate.so`（PDF 文字提取）
- 路径：`app/build/app/outputs/flutter-apk/app-debug.apk`（约 231 MB，debug 多 ABI）

### Windows 构建

```powershell
cd app
flutter build windows --debug
```

结果：构建成功，产物 `app/build/windows/x64/runner/Debug/guwenreader.exe` 可正常启动。

- 窗口标题“古文阅读器”使用 Unicode 转义，避免系统代码页 936 下的编译错误。
- `Runner.rc` 元数据使用 ASCII，避免资源编译器编码问题。

## 2. UI 冒烟

当前环境限制：

- Android 模拟器启动后保持 offline，未成功连接设备。

因此本轮未完成 Android 真实设备 UI 冒烟。Windows 端已通过 `flutter build windows --debug` 构建并启动；根据要求，不再扩展自动化测试或设备测试。

### 2026-11-17 字体、数据目录与 AI 服务商调整

- 全局字体统一为内置 Noto Sans SC（400/500/600/700），移除 `serif` 局部覆盖与提示词预览的 `monospace`。
- 提示词与界面文案统一为简体中文；旧数据库中的英文 claim 枚举会自动生成中文提示词新版本。
- 数据根目录默认改为安装目录的 `data/`：书籍与备份在 `library/`，数据库在 `database/`；旧 AppData 数据首次启动时自动复制。
- 新增“更改数据目录”：迁移数据库、书籍、封面与备份，完成后提示并重启。
- 新增 AI 服务商预设、模型列表读取与多模态能力识别；“添加服务商”改为分区式对话框。
- 导入流程增加文件名、解析阶段、百分比、已用时与失败详情；数据库改为批量写入，FTS 索引分批提交。
- 使用《史记》EPUB（5.2 MB）实测：解析约 1.6 秒，完整导入约 10.4 秒，共 281 章、131,678 句。
- 使用《汉书》EPUB（1.6 MB）实测：完整导入约 4.9 秒，共 120 章、44,668 句。
- Windows 端关闭 Flutter 的 MSAA/UIA 无障碍树，规避 Flutter 3.47 引擎在原生文件对话框关闭时 `AccessibilityBridge::CreateRemoveReparentedNodesUpdate` 的崩溃。
- 书架支持编辑书籍信息与永久删除；使用临时数据库验证删除会清理章节、句子、译文、批注、书签、进度、人物、关系、事件、任务、助手会话、FTS 索引及原始文件。
- AI 流水线使用本地 Mock OpenAI 兼容服务验证：Token/费用计量、翻译短 ID、逐句/批次缓存、任务去重、联合抽取、长章节分块、失败块重试、事件证据合并、重复抽取跳过、单次预算暂停。
- 验证方式：`flutter analyze` 无问题，`flutter test` 36 项通过，`flutter build windows --debug` 成功且应用可打开。

## 3. 验证过的核心路径

- 本地数据库建表、FTS5 创建。
- TXT/EPUB/DOCX 导入与章节/句子构建。
- 全文检索。
- 人工译文保护与候选审核。
- 批注/书签/进度。
- 备份 ZIP 创建与恢复。
- Android APK 编译与原生依赖打包。

## 4. 未验证 / 环境限制

- **Windows 桌面运行**：已构建并启动，字体与数据目录迁移流程待人工逐页确认。
- **Android/iOS UI 冒烟**：模拟器未连接，iOS 需要 macOS。
- **真实 AI 服务**：没有第三方 API Key；AI 流水线使用本地 Mock OpenAI 兼容服务验证，真实 Provider 的模型质量、限流和账单仍需配置密钥后验证。
- **PDF 文字提取运行**：代码已接入 pdfrx/PDFium，APK 中包含原生库，但未在设备上实测文本型 PDF。
- **扫描版 PDF OCR**：明确未实现。
- **Tauri/Rust**：已移除，不再是本项目的一部分。
- **跨设备同步**：已移除服务器同步；当前通过备份 ZIP 迁移。

## 5. 后续验证清单

1. 开启 Windows 开发者模式，`flutter run -d windows`，逐页检查布局与中文显示。
2. 启动 Android 模拟器或连接真机，安装 debug APK，验证导入、阅读、翻译、备份。
3. 配置真实 OpenAI 兼容/Ollama 服务，验证翻译与知识抽取 JSON。
4. 导入文本型 PDF，确认 PDFium 路径。
5. 导入扫描版 PDF，确认被明确拒绝。
6. 创建/导出/恢复备份，确认重启后数据一致。



