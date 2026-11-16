# 古文阅读器

古文阅读器是一个本地优先的 AI 古籍阅读与研究工具：导入古籍，保留原文，逐句对照翻译，并围绕人物、关系与历史事件建立可追溯的知识库。

本项目包含三个完整客户端/服务组件：

- `backend/` — Python 3.12 · FastAPI · SQLAlchemy 2 · SQLite FTS5（可选 PostgreSQL）
- `desktop/` — Tauri 2 · Vue 3 · TypeScript · Vuetify 3 · AntV G6 · ECharts
- `mobile/` — Flutter · Riverpod · Dio · SQLite 本地缓存（Android / iOS 同一套代码）

## 当前状态

已在当前开发环境实际实现并验证：

- 书籍导入：TXT / EPUB / DOCX / 文本型 PDF，内容 SHA-256 去重，原文件完整保留。
- 原文派生：章节识别、段落、句子、字符偏移、规范化文本分层；原始段落/句子永不被翻译覆盖。
- AI 配置：多 Provider、多模型、默认翻译/问答模型、API Key 加密存储、连接测试。
- Prompt：独立文件 + 数据库版本管理，译文记录 Prompt 版本。
- 翻译：章节级任务、动态分批、上下文、缓存、重试、取消、持久化进度、人工译文保护、候选译文审核。
- 阅读器：Windows 双栏句级对应；移动端四种阅读模式；书签、批注、阅读进度按设备保存。
- 知识库：人物、别名、消歧合并、人物关系、史料证据、事件、纪年标准化、时间线。
- 检索：SQLite FTS5 中文全文检索（原文/译文），实体与事件检索。
- AI 助手：基于当前章节、检索到的本地史料回答，输出 citations / claims / 本地来源。
- 同步：设备注册、增量 push/pull、冲突记录与解决、人工译文优先规则；单机模式可选关闭。
- 备份：完整数据 ZIP 备份与停服恢复脚本。

严格的环境限制（未完成即未声称完成）：

- Tauri 原生壳已编写，但当前机器没有 Rust/Cargo，**未编译 Windows 安装包**。
- **iOS 无法在 Windows 上构建/签名**，只提供工程与构建说明。
- Android 调试 APK 的构建结果见 `docs/TEST_REPORT.md`。
- 扫描版 PDF 的 OCR 未实现：会明确报错，不会伪造文本。
- 向量检索 / RAG 尚未实现；当前为 FTS5 + 史料检索。

## 快速开始

### 1. Python 后端

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r backend\requirements.txt
cd backend
..\.venv\Scripts\python.exe -m app
```

- API 文档：http://127.0.0.1:8765/docs
- 默认数据目录：`%APPDATA%\古文阅读器`
- 测试：`cd backend; ..\.venv\Scripts\python.exe -m pytest -q`

### 2. Windows 桌面端（Web 前端）

```powershell
cd desktop\frontend
npm install
npm run dev
```

打开 http://127.0.0.1:1420 。默认连接 `http://127.0.0.1:8765/api/v1`，可在“设置 → 服务与同步”修改。

Tauri 原生壳位于 `desktop/src-tauri/`。安装 Rust/Cargo 后：

```powershell
cd desktop\src-tauri
cargo tauri build
```

### 3. Android / iOS

```powershell
cd mobile
flutter pub get
flutter run -d <device>
```

Android 模拟器默认后端地址为 `http://10.0.2.2:8765/api/v1`；真机请在“我的 → 后端服务”填写电脑局域网 IP。iOS 模拟器默认 `127.0.0.1`。

## 设计原则

1. **原文完整保留**：翻译、繁简转换和检索均不修改原始文本；句子/段落保存提取文本中的精确字符偏移。
2. **译文精确关联**：译文按 sentence id 与原文关联，不使用滚动比例猜测对应关系。
3. **知识有据可查**：AI 抽取的实体、关系、事件保留句子证据和审核状态；推断不会自动变成事实。
4. **本地优先**：桌面内置后端；移动端缓存书籍章节、译文、批注和进度，可离线阅读。
5. **云端可选**：不配置服务器也能阅读；配置 Server 模式后启用多设备同步。
6. **模型可替换**：Provider 适配层不绑定任何厂商；OpenAI 兼容接口和 Ollama 均可配置。

## 文档

- [架构](docs/ARCHITECTURE.md)
- [数据库](docs/DATABASE.md)
- [API](docs/API.md)
- [AI Prompt](docs/AI_PROMPTS.md)
- [构建与发布](docs/BUILD.md)
- [开发计划与完成情况](docs/DEVELOPMENT_PLAN.md)
- [测试报告](docs/TEST_REPORT.md)
- [桌面端说明](desktop/README.md)
- [移动端说明](mobile/README.md)

## 安全与隐私

- API Key 在 Windows 上使用 DPAPI 加密；服务器模式使用由 `GUWEN_SECRET_KEY` 派生的 Fernet 密钥；不会出现在 API 响应、日志或错误消息中。
- 日志会过滤 `sk-*`、Authorization、api_key 等敏感模式。
- 所有 AI 调用都由用户自己配置的 Provider 发起；项目不含隐藏遥测。
- 备份 ZIP 含完整原文与知识数据，请自行妥善保管。

## License

见 [LICENSE](LICENSE)。
