# 古文阅读器桌面端

Windows 桌面端：Tauri 2 + Vue 3 + TypeScript + Vuetify 3 + AntV G6 + ECharts。

## 功能

- 书架：导入 TXT/EPUB/DOCX/PDF、搜索、分类、标签、翻译进度、继续阅读。
- 书籍详情：元数据、章节目录、翻译状态、知识抽取入口。
- 阅读器：原文/译文双列精确对齐、句级联动、状态占位、章节导航、字体/行距/主题。
- 句子详情：原文、译文、人工修订、重翻译、候选审核、版本历史、批注、AI 解释。
- AI 服务：Provider/Model 管理、连接测试、默认模型、Prompt 版本管理。
- 知识：人物知识库、G6 关系图谱、ECharts 时间线、全文检索、AI 助手。
- 任务中心：实时 WebSocket 进度、取消、失败统计。
- 设置：Server 登录、设备、同步状态、完整数据备份。
- 本地优先：默认连接 Embedded 后端；可切换 Server API 地址。

## 开发

```powershell
npm install
npm run dev
```

默认 API `http://127.0.0.1:8765/api/v1`，可在“设置 → 服务与同步”修改。

构建：

```powershell
npm run typecheck
npm run build
```

## Tauri

`src-tauri/` 包含：

- `tauri.conf.json`：窗口、CSP、资源打包、NSIS 配置。
- `src/lib.rs`：从 `<resource_dir>/backend/guwenreading-backend.exe` 启动 sidecar，关闭窗口时终止。
- `capabilities/default.json`：最小权限。
- 图标：`icons/`。

构建前置：

1. 安装 Rust/Cargo 与 Tauri CLI。
2. 运行 `scripts/build_backend.ps1` 生成 sidecar。
3. `cargo tauri build`。

**未验证**：当前仓库生成环境没有 Cargo，未生成 Windows 安装包，也未验证 sidecar 打包路径。

## 结构

```
src/
  api/          Axios 客户端与领域 API
  stores/       Pinia（应用设置、书架、AI、任务）
  layouts/      MainLayout
  views/        Library / BookDetail / Reader / Search / Entities / Graph / Timeline / Notes / Tasks / Settings
  components/   BookCard / ImportDialog / SentencePanel / AssistantDrawer / EmptyState
  layouts/
  plugins/      Vuetify 主题
  styles/       全局阅读与桌面样式
```
