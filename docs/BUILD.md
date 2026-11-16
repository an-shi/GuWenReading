# 构建与发布

## 环境要求

| 组件 | 版本/要求 | 当前验证环境 |
| --- | --- | --- |
| Python | 3.12+ | 3.12.0 |
| Node.js | 20+ | 24.11.0 |
| Flutter | 3.35+ | 3.47.9 / Dart 3.13.7 |
| Android SDK | API 34+ | API 36，build-tools 36 |
| Rust / Cargo | Tauri 2 构建需要 | **未安装，未编译验证** |
| iOS | macOS + Xcode | **Windows 环境无法构建** |

## 1. 后端

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r backend\requirements.txt
cd backend
..\.venv\Scripts\python.exe -m app
```

默认：

- 监听 `127.0.0.1:8765`
- 数据目录 `%APPDATA%\古文阅读器`
- SQLite 数据库 `%APPDATA%\古文阅读器\guwen.db`

常用环境变量：

```powershell
$env:GUWEN_MODE = "embedded"          # embedded | server
$env:GUWEN_HOST = "0.0.0.0"           # Server 模式
$env:GUWEN_PORT = "8765"
$env:GUWEN_DATA_DIR = "D:\古文阅读器-data"
$env:GUWEN_DATABASE_URL = "postgresql+asyncpg://user:pass@host/guwenreading"
$env:GUWEN_SECRET_KEY = "long-random-secret"   # 生产必须设置
$env:GUWEN_AUTO_CREATE_SCHEMA = "false"        # Server 模式推荐；先用 Alembic
$env:GUWEN_CORS_ORIGINS = "https://your-desktop-origin"
```

### 数据库迁移

```powershell
cd backend
..\.venv\Scripts\python.exe -m alembic upgrade head
```

### 后端测试

```powershell
cd backend
..\.venv\Scripts\python.exe -m pytest -q
```

当前结果：48 passed（见 `docs/TEST_REPORT.md`）。`alembic check` 无差异。

### PyInstaller sidecar

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build_backend.ps1
```

输出：`desktop/src-tauri/resources/backend/guwenreading-backend/guwenreading-backend.exe`。脚本使用 onedir + 收集 Prompt 资源；尚未在当前环境执行完整打包验证。

## 2. Windows 桌面端

```powershell
cd desktop\frontend
npm install
npm run typecheck
npm run build
npm run dev
```

- 前端构建已验证通过（Vite 生产构建）。
- 默认 API：`http://127.0.0.1:8765/api/v1`；可在设置中修改并保存到本机。
- 使用浏览器/CORS 或 Tauri WebView 均可。

### Tauri

```powershell
# 需安装 Rust + Tauri CLI
cd desktop\src-tauri
cargo tauri build
```

`tauri.conf.json` 会把 `resources/backend/` 打包为 sidecar 资源；Rust shell 在启动时尝试：

```
<resource_dir>/backend/guwenreading-backend.exe
```

若文件不存在，则假定后端由开发环境或用户单独启动。关闭主窗口时终止 sidecar。

**当前限制**：本仓库快照生成环境没有 Cargo，因此未编译、未生成 `.msi/.exe` 安装包，也未实际验证 sidecar 启动。

## 3. Android

```powershell
cd mobile
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

- 默认 API：模拟器 `http://10.0.2.2:8765/api/v1`；真机需填写电脑局域网 IP。
- 允许明文 HTTP 仅用于本地/局域网后端（`android:usesCleartextTraffic="true"`）；生产可改为 HTTPS 并收紧。
- 已设置 `minSdk = 23`、INTERNET 权限。
- `pubspec.yaml` 的 sqlite3 hooks 使用系统 SQLite，避免构建时从未访问的 GitHub 下载原生库；应用运行时数据库仍由 sqflite 插件提供。
- 发布签名：在 `mobile/android/key.properties` 配置 keystore，并按 Flutter 官方文档修改 `signingConfigs`；本仓库未包含签名密钥。

当前环境已成功构建最终调试 APK（含应用图标、备份、离线测试依赖）：

```
mobile/build/app/outputs/flutter-apk/app-debug.apk
```

## 4. iOS

必须在 macOS + Xcode 上执行：

```bash
cd mobile
flutter pub get
flutter build ios --release
# 或使用 Xcode 配置 Team / Bundle ID / 签名后 Archive
```

已配置：

- `CFBundleDisplayName = 古文阅读器`
- `NSLocalNetworkUsageDescription`
- ATS 允许 HTTP（本地/局域网后端）

**当前限制**：Windows 环境无法构建或签名 iOS；未声称 iOS 安装包已验证。

## 5. 数据与备份

- 数据目录包含 `guwen.db`、`books/`、`covers/`、`backups/`、`logs/`、`tmp/`。
- 桌面端设置页可创建完整 ZIP 备份。
- 恢复前停止后端：

```powershell
.\.venv\Scripts\python.exe scripts\restore_backup.py D:\backups\古文阅读器备份-....zip
```

脚本会先保存当前数据到 `data/backups/pre-restore-*`。

## 6. 发布检查清单

- [x] 后端测试通过
- [x] 桌面前端类型检查/生产构建通过
- [x] Flutter analyze 无问题、单元测试通过
- [x] Android debug APK 构建（final）
- [ ] Android release 签名 APK
- [ ] iOS release 构建/签名
- [ ] Tauri Windows 安装包
- [ ] 大文件/10 万句级性能基准
- [ ] 真实第三方 AI 服务端到端测试（本环境仅用 mock 验证）
