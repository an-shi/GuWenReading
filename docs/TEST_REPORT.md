# 测试报告

日期：2026-11-16

## 1. 自动化测试

### 后端

```powershell
cd backend
..\.venv\Scripts\python.exe -m pytest -q
```

结果：

```
48 passed
```

覆盖范围：

- 断句/偏移/原文重建；繁简转换不修改原文。
- TXT 编码、EPUB、DOCX、文本型 PDF 与扫描版 PDF 拒绝。
- 导入、重复文件、偏移一致性、搜索、批注、书签、按设备进度、软删除、重解析保护。
- Provider/Key 加密与不泄露；Prompt 版本管理。
- 章节翻译、人工修订、重翻译候选、候选接受、缓存命中、失败状态、任务事件。
- 纪年换算/歧义、实体/关系/事件抽取、证据、图谱、时间线、AI 助手引用。
- 实体合并。
- Server 模式认证、设备注册、JWT。
- 同步 push/pull、人工译文保护、冲突、accept server/client、设备进度隔离。
- 完整备份 ZIP 内容。

### 桌面端

```powershell
cd desktop/frontend
npm run typecheck
npm run build
```

- 类型检查通过。
- Vite 生产构建通过。
- 全中文界面修改后重新执行 `typecheck` 与 `build`，均通过。
- 产品名称统一为古文阅读器后再次执行，均通过；构建产物与浏览器标题均无旧品牌文本。

### 数据库迁移

```powershell
cd backend
$env:GUWEN_DATA_DIR = "<temp>"
..\.venv\Scripts\python.exe -m alembic upgrade head
..\.venv\Scripts\python.exe -m alembic check
```

- 初始迁移成功创建全部业务表与 `search_fts`。
- `alembic check`：No new upgrade operations detected（FTS5 shadow tables 已从 autogenerate 比较中排除）。

### 移动端

```powershell
cd mobile
flutter analyze
flutter test
flutter build apk --debug
```

结果：

- `flutter analyze`：No issues found。
- `flutter test`：5 tests passed（模型解析、阅读模式、离线书架回退、本地批注/书签/进度、直连译文合并）。
- Android debug APK：构建成功（含应用图标、离线缓存与直连翻译代码）。
  - `mobile/build/app/outputs/flutter-apk/app-debug.apk`（约 167 MB，debug/多 ABI）
  - 全中文界面与产品名称统一后重新构建；`aapt dump badging` 验证 `package=com.guwenreading.mobile`、`application-label=古文阅读器`。

## 2. UI 冒烟测试

桌面端使用真实后端 + 开发用 OpenAI 兼容 mock 服务，在 Chromium 中逐页验证：

- 书架：数据、分类、搜索、导入对话框、继续阅读。
- 书籍详情：元数据、章节列表、翻译进度、知识抽取入口。
- 阅读器：原文/译文双列、句级点击、句子详情、人工译文、状态、章节导航、设置。
- AI 助手：真实 HTTP 调用 mock → 回答、claims、citations、本地史料数量。
- 图谱：G6 渲染、节点点击、关系证据侧栏。
- 时间线：ECharts 渲染、事件详情、未定时间列表。
- 人物知识库：自动选择、详情、关系/提及、合并入口。
- 搜索：原文/译文/实体/事件结果与高亮。
- 设置：服务商/模型、提示词版本、主题、字体、服务/同步、备份。
- WebSocket 任务完成通知。
- 完整备份创建；使用 `scripts/restore_backup.py --data-dir <temp>` 实际恢复 ZIP 并验证数据库与书籍目录。

### 全中文界面检查（2026-11-16）

桌面端在 Chromium 中重新逐页检查，移动端通过源码扫描与 `flutter analyze`/`flutter test` 验证：

- 句子详情：`SENTENCE`、`TRANSLATION`、`ANNOTATIONS`、`PENDING REVIEW`、`AI EXPLANATION`、`VERSION HISTORY` 已改为“句子、译文、批注、待审核候选、AI 解释、版本历史”；`Prompt v1` 改为“提示词 v1”。
- 页面分区标签：书架、书籍详情、阅读器、检索、批注、任务、设置、人物知识库、关系图谱、时间线中的英文 eyebrow 标签已全部替换为中文。
- 设置页：Provider 类型、服务模式、能力列表显示为中文；`API Base URL`/`API Key` 显示为“接口地址/接口密钥”，`tokens` 显示为“词元”，`Server/Embedded` 显示为“服务端/内嵌”，`Prompt` 显示为“提示词”。
- 枚举展示：实体类型、关系审核状态、任务结果字段、知识库人物类型均经显示层映射为中文；后端枚举值和持久化数据未改动。
- 移动端：书架原英文装饰标签改为“古籍典藏”，接口地址、密钥、设备编号、服务模式等标签同步中文化。
- 布局检查：上述页面未发现新增文字溢出、截断或错位；中文字符串长度变化未破坏双栏阅读器与设置网格。
- 保留项：`古文阅读器`、`OpenAI`、`Ollama`、`TXT/EPUB/DOCX/PDF`、模型名、URL、提示词模板内的 JSON 字段与 AI 输出枚举属于品牌或技术契约，不翻译。

### 产品名称统一为古文阅读器（2026-11-16）

- 桌面端侧栏、浏览器标题、Tauri 窗口标题与产品名、移动端应用名、关于页、Android 应用标签、iOS 显示名称均已改为古文阅读器。
- 后端 `system/info` 的应用名、FastAPI 文档标题、备份元数据与构建脚本描述同步更新。
- 技术标识同步更新：Tauri identifier、PyInstaller sidecar 名称、npm/Cargo/Flutter 包名、Android applicationId、iOS bundle ID 使用 ASCII；备份前缀改为“古文阅读器备份”，备份格式与移动端本地数据库文件名保留 ASCII 技术标识。
- 默认数据目录改为 `%APPDATA%\古文阅读器`。
- 启动时会自动将历史提示词中的旧品牌名称替换为古文阅读器，避免已有数据库继续显示旧名称。
- 已实际验证：桌面标题与侧栏、后端 `system/info`、FastAPI 标题、提示词内容、备份文件名/元数据、恢复脚本、Android 应用标签均为古文阅读器；Android 包名为 ASCII 技术标识 `com.guwenreading.mobile`。
- 复测结果：后端 48 passed；桌面 `typecheck`/`build` 通过；Flutter analyze 无问题、5 tests passed；debug APK 构建成功。

移动端在 Android 16 模拟器安装 debug APK：

- 书架从 `10.0.2.2:8765` 成功读取真实数据；离线/在线状态正常。
- 书籍详情、章节目录、阅读器（交替模式与逐句模式）已在模拟器验证；句子详情底部弹层与 AI 解释入口正常。
- 离线回退逻辑通过 sqflite_ffi 单元测试验证；知识/任务/设置页面未在模拟器逐页截图验证。

## 3. 测试过程中修复的问题

1. **FTS5 未启用**：驱动检查使用 `aiosqlite` 而实际为 `sqlite+aiosqlite`，导致表未创建、静默回退 LIKE；已修复并增加启动索引回填、检索高亮测试。
2. **Vuetify 组件未注册**：新版 Vuetify 不再自动注册全部组件；显式注册 components/directives，修复侧栏和布局。
3. **阅读器句间空白**：模板空白 + padding 造成中文句子间空格；通过容器字号 0 + 句子字号恢复和去除 padding 修复。
4. **同步设备读取表达式优先级**：`a == b or c` 导致 SQLite 错误；加括号修复并测试。
5. **历史译文版本在重解析时被级联删除**：取消 version 对 sentence 的外键，保留历史版本。
6. **Android 构建增量缓存错误**：禁用 Kotlin incremental 后重新构建成功。
7. **移动端 FilePicker v13 API 变化**：改用静态 `FilePicker.pickFiles` 与 `PlatformFile.readAsBytes()`。
8. **Task 列表 page_size 超限**：前端请求 200 而 API 最大 100，修复为 100。
9. **sqflite_common_ffi 触发原生 SQLite 下载失败**：Flutter 构建从 GitHub 拉取 sqlite3 二进制失败；在 pubspec 中配置 `hooks.user_defines.sqlite3.source: system` 使用系统 SQLite 后，离线单测与 APK 构建均通过。
10. **中文本地化乱码**：控制台显示受 Windows 代码页影响，实际 API/文件为 UTF-8；不影响应用。

## 4. 未验证 / 环境限制

- **真实 AI 服务商**：没有可用的第三方 API Key；所有 AI 全链路验证使用本地 mock OpenAI 服务器。Provider 网络错误、401、超时、缓存、任务状态是真实代码路径。
- **iOS**：Windows 环境无法构建/签名。
- **Tauri Windows 安装包**：无 Rust/Cargo，未编译原生壳。
- **扫描版 PDF OCR**：明确未实现。
- **超大文件/10 万句**：未做基准；当前批量插入与 FTS 索引已按批处理，但未量化。
- **Android release 签名**：未配置 keystore。
- **多设备真机同步**：后端测试覆盖，未用两台真实设备联调。
- **真实网络中断/后台限制**：模拟器有限验证，未做长时间移动网络切换测试。
