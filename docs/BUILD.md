# 构建与发布

最后更新：2026-11-16

## 1. 环境

- Flutter 3.47+ / Dart 3.13+
- Windows：Visual Studio，Windows 10/11 SDK
- Android：Android SDK 36、JDK 17
- iOS/macOS：Xcode（仅 macOS）

项目只有一个 Flutter 应用：`app/`。没有 Python、Node 后端或 Tauri。

## 2. 依赖

```powershell
cd app
flutter pub get
```

主要依赖：

- Riverpod、Dio、sqflite / sqflite_common_ffi
- archive、xml、html、charset_converter
- pdfrx（PDF 文字提取，内置 PDFium）
- graphview、fl_chart
- file_picker、path_provider、flutter_secure_storage、shared_preferences

## 3. Windows 桌面端

### 3.1 开启开发者模式

Flutter Windows 插件构建需要符号链接支持。请打开：

```powershell
start ms-settings:developers
```

开启“开发者模式”。未开启时 `flutter build windows` 会报：

```text
Building with plugins requires symlink support.
```

### 3.2 运行/构建

```powershell
cd app
flutter run -d windows
flutter build windows --release
```

产物在 `app/build/windows/x64/runner/Release/`。

首次构建会编译 SQLite/PDFium 等原生依赖，可能需要数分钟。

### 3.3 图标

```powershell
cd app
dart run flutter_launcher_icons
```

已配置 Android、iOS、Windows 图标。

## 4. Android

```powershell
cd app
flutter build apk --debug
flutter build apk --release
```

- 包名：`com.guwenreading.app`
- 应用名：古文阅读器
- release 需要自行配置 keystore；当前未提供签名文件。

## 5. iOS

```bash
cd app
flutter build ios
```

需要 macOS、Xcode 与 Apple 开发者签名。Windows 环境无法构建。

## 6. 数据目录

- Windows：应用支持目录（通常位于 `%APPDATA%` 下）中的 `古文阅读器/`
- Android/iOS：应用私有支持目录下的 `古文阅读器/`

数据库、原始书籍、封面、备份与临时文件均在此目录。

## 7. 发布检查

- [ ] `flutter analyze` 无问题
- [ ] `flutter test` 全部通过
- [ ] Windows：开启开发者模式后构建并运行
- [ ] Android：debug/release APK 安装与阅读闭环
- [ ] iOS：Xcode 构建与签名
- [ ] 导入 TXT/EPUB/DOCX/文本型 PDF
- [ ] 配置真实 AI 服务，测试翻译、知识抽取、助手
- [ ] 创建备份、导出、恢复
- [ ] 确认扫描版 PDF 被明确拒绝
- [ ] 确认无明文 API Key、无未预期网络请求

## 8. 已知构建限制

- 当前 Windows 环境未开启开发者模式，`flutter build windows` 未完成验证。
- 当前环境没有可用的 Android 模拟器/真机，APK 只完成构建验证。
- PDFium 首次构建需要下载原生库；网络不稳定时会重试。
- 扫描版 PDF 的 OCR 未实现。
