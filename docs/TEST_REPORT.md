# 测试报告

日期：2026-11-16

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

结果：**未完成**。

```text
Building with plugins requires symlink support.
Please enable Developer Mode in your system settings.
```

当前 Windows 账户无管理员权限，无法通过注册表开启开发者模式。需要在系统中手动开启后重新构建。

## 2. UI 冒烟

当前环境限制：

- Windows 构建被开发者模式阻塞。
- Android 模拟器启动后保持 offline，未成功连接设备。

因此本轮未完成真实设备 UI 冒烟。已通过 `flutter analyze`、10 项自动化测试（含移动端/桌面端应用壳 widget 测试）和 APK 构建验证代码路径；真实设备 UI 运行验证需在开启开发者模式或可用 Android 设备后补做。

## 3. 验证过的核心路径

- 本地数据库建表、FTS5 创建。
- TXT/EPUB/DOCX 导入与章节/句子构建。
- 全文检索。
- 人工译文保护与候选审核。
- 批注/书签/进度。
- 备份 ZIP 创建与恢复。
- Android APK 编译与原生依赖打包。

## 4. 未验证 / 环境限制

- **Windows 桌面运行**：开发者模式未开启。
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
