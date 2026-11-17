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

结果：`10 tests passed`

覆盖：

- TXT 导入：元数据、章节、段落、句子、FTS 检索。
- 人工译文保护与 AI 重译候选审核。
- 批注、书签、阅读进度本地持久化。
- EPUB 导入：OPF/spine/XHTML、书名/作者、章节文本。
- DOCX 导入：WordprocessingML 段落文本。
- 备份创建、列表与恢复；恢复后数据状态一致。
- 阅读模式映射与章节内容序列化。
- 移动端/桌面端应用壳启动：底部导航与 NavigationRail。

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
- 验证方式：`flutter analyze` 无问题，`flutter build windows --debug` 成功且应用可打开。

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
- **真实 AI 服务**：没有第三方 API Key；翻译、知识抽取、助手的 HTTP/JSON 路径未做真实服务端到端验证。
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
