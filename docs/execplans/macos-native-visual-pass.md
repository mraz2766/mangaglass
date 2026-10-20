# ExecPlan：macOS 原生视觉整理

## 摘要

从 macOS HIG 角度整理 MangaGlass 的视觉层级、控件语言与侧栏/设置的原生感。只改视图层，不改任何业务逻辑、网络、下载或持久化行为。性能问题只出建议，等用户确认后再动。

## 用户价值

- 侧栏像 Finder/Music 一样有文字标签，不再靠猜图标；队列数量用徽标显示，不再重复一个托盘图标。
- 章节网格从「每格都是带底色的卡片」变成安静的列表格子，选中态清楚、未选态不吵。
- 设置页变成系统设置式的分组表单，对齐自动整齐。
- 跟随系统强调色（用户在系统设置里选的颜色）。
- 四个页面标题、间距、按钮高度统一。

## 范围

范围内：

- `DesignSystem.swift`：强调色改 `Color.accentColor`；统一按钮高度 28；章节格子去描边、降高度；新增 `MGPageHeader`；字号表整理。
- `WorkspaceChrome.swift`：侧栏改为 `List(.sidebar)` + 文字标签 + 队列徽标 + 下载中进度脚注。
- `ContentView.swift`：侧栏宽度、窗口最小尺寸、分隔线。
- `DownloadWorkspaceView.swift`：移除工具栏「•••」状态点；下载目录行对齐；网格间距。
- `QueueWorkspaceView.swift`：统一页头；筛选改原生分段控件；行内章节为主、漫画名为辅；状态右置。
- `HistoryAndSettingsWorkspace.swift`：历史行降噪；设置改 `Form(.grouped)`。
- `AppDelegate.swift`：最小窗口尺寸同步。
- `Tests/MangaGlassTests/LayoutSnapshots.swift`：侧栏宽度同步。

范围外：

- 任何 ViewModel / Coordinator / Service 逻辑。
- 性能优化（只写建议）。

## 约束

- 大幅度 UI 改版：版本 `1.8.5` → `1.9.0`。
- 最低系统 macOS 13：只用 13 可用 API（`Form.formStyle(.grouped)`、`List.badge` 均可用）。
- 构建后替换 `/Applications/MangaGlass.app`，中文 `feat:` 提交。

## 实施计划

1. 设计系统 token 与控件样式。
2. 侧栏 + 外壳。
3. 首页 / 队列 / 历史 / 设置逐页套用。
4. 快照测试渲染浅色/深色对比，构建安装，提交。

## 验证方式

- `swift build`、`swift test`
- `MANGAGLASS_SNAPSHOT_DIR=… swift test --filter LayoutSnapshots` 对比前后截图（浅/深色）。
- `scripts/build_app.sh --install`

## 决策记录

- 侧栏宽度 176 → 窗口最小宽度由 720×540 提到 880×560，保证首页封面列 + 章节网格仍可用。
- 「•••」活动点在空闲时像「更多」菜单，属于误导性装饰；解析中状态已由「解析」按钮内 spinner 和左栏状态行表达，故移除。

- 侧栏最初用 `List(.sidebar)`，快照中非 key 窗口的选中行渲染成黑块、文字不可见；改为自绘 source-list 行（28pt 行高、6pt 圆角、强调色图标、灰色选中底）+ `NSVisualEffectView(.sidebar)` 背景，表现确定。
- 设置页下载目录的完整路径从常驻说明改为悬停提示，减少一行噪音。

## 结果

- 版本 `1.9.0`，已构建并替换 `/Applications/MangaGlass.app`。
- `swift test`：38 项通过（2 项按设计跳过）；`LayoutSnapshots` 浅/深色 × 多尺寸渲染通过并人工比对。
- 侧栏：图标轨 → 带文字的 source list，队列数量改为行尾数字，删除底部重复托盘按钮；下载中才显示进度脚注。
- 首页：删除误导性「•••」状态点；章节格 38→30pt、去选中描边、间距 8→4；下载目录改为一行次级文字。
- 队列：统一页头；筛选改原生分段控件；行以章节为主、漫画名为辅，状态右置。
- 历史：去掉蓝色书本图标与等宽 URL 行，合并为一行元信息。
- 设置：改为 `Form(.grouped)`，通用/下载/访问/其他四组，控件改原生弹出菜单。
- 全局：强调色跟随系统；按钮统一 28pt；页标题统一 20pt semibold。
