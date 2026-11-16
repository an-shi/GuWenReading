# 古文阅读器移动端

Flutter Android/iOS 客户端。与 Windows 客户端、Server 后端共享同一 API 契约。

## 功能

- 书架与书籍详情，导入文件（通过后端解析）、下载整本。
- 本地 SQLite 缓存：书籍列表、章节内容、译文、直连译文、批注、书签、进度。
- 四种阅读模式：
  1. 原文译文交替（默认）
  2. 原文优先（点击段落查看译文）
  3. 原文/译文独立切换
  4. 逐句对照
- 模式切换按段落索引保持阅读位置；ScrollablePositionedList 虚拟化长章节。
- 句级详情、AI 解释、批注、书签、阅读进度（本地 + 服务端按设备）。
- 翻译状态、共享后端任务、取消、轮询；章节内搜索、TOC。
- 三种 AI 翻译方式：
  - 后端共享
  - 手机直连 OpenAI 兼容接口
  - 混合（优先后端，失败时直连）
- 知识库人物/事件浏览、人物关系与史料、AI 阅读助手。
- 设置：API 地址、Server 登录、主题/字号/行距、直连 AI、本地数据、设备 ID。

## 运行

```powershell
flutter pub get
flutter run -d <device>
```

Android 模拟器后端地址：`http://10.0.2.2:8765/api/v1`。真机请填电脑局域网 IP（后端需监听 `0.0.0.0` 或允许局域网访问），并确保防火墙放行。

## 构建

```powershell
flutter analyze
flutter test
flutter build apk --debug
# release: 配置 keystore 后 flutter build apk --release
```

iOS 只能在 macOS：

```bash
flutter build ios --release
```

## 本地缓存与同步

- 章节内容缓存 key：`chapter:<chapterId>`；书籍列表与章节列表也缓存。
- 离线时阅读已缓存章节；AI 翻译与知识库需要网络或本地直连模型。
- 批注/书签先写本地；离线创建标记 dirty，联网后在应用启动/恢复时推送。
- 阅读进度始终先写本地，并尝试推送到服务端；服务端按 `device_id` 隔离。
- 清除缓存会删除已下载章节与直连译文，**不会**删除批注、书签、进度。

## 限制

- 扫描版 PDF 的 OCR 未实现。
- 移动端直连仅支持 OpenAI Chat Completions 兼容接口。
- 未实现完整的 sync pull / 冲突解决 UI；知识库页面需要在线后端。
- 后台翻译由后端继续执行；APP 自身不在后台长时间运行翻译任务。

## 结构

```
lib/
  app/           主题、AppShell、导航
  core/          API 客户端、SQLite、设置/安全存储
  data/          模型、仓库、直连 AI
  domain/        阅读模式
  features/      bookshelf / book_detail / reader / knowledge / tasks / settings
  providers.dart Riverpod providers
```
