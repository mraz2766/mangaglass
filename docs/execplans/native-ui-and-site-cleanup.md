# ExecPlan：原生界面优化与失效站点清理

## 摘要

移除已经不可用的 2025 拷贝漫画站点，将保留站点命名为“主站”和“备用站”。在不改变下载、队列、历史和设置业务结构的前提下，统一四页的层级、尺寸、状态与滚动行为。

## 用户价值

- 不再向失效站点发起解析或下载请求。
- 章节区域不再裁切，选择与批量操作更清晰。
- 四个页面更接近 macOS 原生应用，减少多余卡片、描边和重复状态。

## 范围

范围内：站点枚举、输入与旧任务拦截、下载页响应式布局、队列/历史/设置/侧边栏样式、文档、版本、构建安装。

范围外：下载协议重构、持久化格式迁移、新功能入口。

## 约束

- 保持 macOS 13 与当前 SwiftUI 架构兼容。
- 本次为显著 UI 改版，版本从 `1.3.3` 升至 `1.4.0`，两个 Bundle 版本保持一致。
- 完成后必须构建并替换 `/Applications/MangaGlass.app`，随后提交中文 `feat:` commit。

## 修改文件

- `Sources/MangaGlass/Models/MangaModels.swift`
- `Sources/MangaGlass/App/MainViewModel.swift`
- `Sources/MangaGlass/UI/DesignSystem.swift`
- `Sources/MangaGlass/UI/Workspace/*.swift`
- `Sources/MangaGlass/UI/ContentView.swift`
- `README.md`、`README.zh-CN.md`、`scripts/build_app.sh`
- `docs/execplans/native-ui-and-site-cleanup.md`

## 已确认事实

- `CopyMangaMirror` 当前包含 2025，并通过 `allCases` 进入菜单和网络回退。
- 下载页当前根据整个工作区宽度固定列数，可能超过章节容器可用宽度。
- 当前版本为 `1.3.3`，默认窗口为 `1080 × 760`，最小窗口为 `720 × 540`。

## 实施计划

### 里程碑 1：清理失效站点

- 仅保留主站和 2026 备用站，并在解析、恢复与重试前拦截 2025 链接或旧任务。
- 同步文档和所有支持域名列表。

### 里程碑 2：统一设计系统与侧边栏

- 使用系统语义色、统一字体、间距、按钮高度、圆角和悬停状态。
- 降低侧边栏与队列摘要的容器噪音。

### 里程碑 3：重排四个页面

- 下载页采用响应式漫画摘要与自适应章节网格，固定操作栏不覆盖列表。
- 队列、历史和设置统一信息密度、操作层级与内容宽度。

### 里程碑 4：验证与交付

- 运行构建与逻辑检查，安装应用，核对版本，更新本计划结果并提交。

## 验证方式

- `swift build`
- `bash scripts/build_app.sh --install`
- 检查应用 plist 两个版本均为 `1.4.0`。
- 搜索生产代码和 README，确认 2025 仅保留在停用识别中。

## 风险

- 旧队列中的站点信息可能仍包含 2025，因此所有恢复与重试入口必须统一拦截。
- SwiftUI macOS 13 缺少原生流式布局，分类筛选采用自适应网格实现换行。

## 决策记录

- 决策：旧 2025 链接提示停用，不自动改写到 2026。
  原因：用户已明确选择该行为。
- 决策：章节列数交给自适应 `LazyVGrid` 按实际容器宽度计算。
  原因：消除固定列数带来的右侧裁切。

## 进度

- [x] 创建并保存 ExecPlan。
- [x] 完成主要实现。
- [x] 完成验证。

## 意外发现

- 仓库原有 `.build` 缓存记录了旧工作区路径，直接执行 `swift build` 会触发 `SwiftShims` 模块缓存路径错误；改用独立临时 scratch path 验证后通过，并恢复了构建命令造成的 `.build` 跟踪变动。
- `underPageBackgroundColor` 在当前浅色外观下对章节主面板过深，实际运行检查后统一改用 `controlBackgroundColor`。

## 结果与回顾

- 拷贝漫画入口和网络回退仅保留主站与 2026 备用站；2025 仅作为停用域名识别常量存在。
- 旧输入、旧历史加载、旧队列恢复、继续下载和失败重试均在请求前拦截。
- 下载页使用自适应章节网格与滚动区外固定操作栏，队列、历史、设置和侧边栏完成统一视觉调整。
- `swift build --scratch-path /tmp/mangaglass-ui-build` 通过。
- `bash scripts/build_app.sh --install` 通过，已替换 `/Applications/MangaGlass.app`。
- `/Applications/MangaGlass.app` 的 `CFBundleShortVersionString` 与 `CFBundleVersion` 均为 `1.4.0`。
- 使用安装后的应用检查四个页面，并验证 2025 链接显示“2025 站点已停用，请使用主站或备用站链接。”。
