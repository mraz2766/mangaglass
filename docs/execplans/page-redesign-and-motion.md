# ExecPlan：页面改版 + 动效 + 经典主题玻璃化

## 摘要

按用户确认的草图方案改造四个页面的布局与动效，并把「经典」主题改为白 + 蓝的玻璃质感。业务逻辑（解析、选择规则、下载、队列持久化）不变。

## 用户价值

- 首页空状态：居中大输入框 +「继续上次」封面行，第一眼知道做什么。
- 解析后：封面缩进标题区，章节网格占满宽度；分类改为标签行；底部浮动选择胶囊。
- 下载页：总进度（百分比 / 速度 / 剩余时间）置顶，任务按漫画分组。
- 历史 → 书架：封面网格。
- 设置：主题改为带预览的卡片。
- 经典主题：窗口背后磨砂玻璃，白色半透明面板，系统蓝强调。
- 动效：页面切换、侧栏选中滑块、骨架屏、章节依次出现、按压回弹、勾选弹出、选择胶囊弹入、数字飞入下载图标、进度平滑、失败抖动、书架悬停浮起；全部尊重「减少动态效果」。

## 范围

- 修改：`MangaModels.swift`（`RecentComicRecord.coverURL` 可选字段，旧数据兼容）、`MainViewModel.swift`（记录封面）、`ThemePalette.swift`、`DesignSystem.swift`、`ContentView.swift`、`WorkspaceChrome.swift`、`DownloadWorkspaceView.swift`、`QueueWorkspaceView.swift`、`HistoryAndSettingsWorkspace.swift`、`LayoutSnapshots.swift`。
- 新增：`UI/Motion.swift`（骨架、依次出现、抖动、飞入层）。
- 范围外：下载/解析/队列逻辑；侧栏结构（保留图标栏）。

## 约束

- 显著 UI 改版：`1.11.0` → `1.12.0`。
- macOS 13 API；`matchedGeometryEffect`、`TimelineView` 可用。
- 动效时长 0.15–0.35s，`accessibilityReduceMotion` 时降级为淡入或无动画。

## 实施计划

1. 数据：书架需要封面 → 记录 `coverURL`。
2. 主题：经典 = 玻璃画布（`NSVisualEffectView` behindWindow）+ 白色半透明面板 + 系统蓝实色选中。
3. 动效基元。
4. 外壳：侧栏选中滑块、导航改名「下载」「书架」、飞入层。
5. 首页、下载页、书架、设置依次改版。
6. 快照核对 3 主题 × 浅/深，构建安装，提交。

## 验证

- `swift test`；`LayoutSnapshots` 渲染首页（空/解析中/已解析/错误）、下载、书架、设置。
- `scripts/build_app.sh --install`。

## 决策记录

- 搜索与排序并入标题区的分类标签行，去掉单独的「卷与章节」行（与「全部 N」重复），网格多出约一行。
- 分类标签交互：从「全部」点某卷 → 只看该卷；只剩一卷时再点 → 回到全部；其余为多选切换。仅组合调用既有 vm 方法。
- 经典主题的玻璃效果依赖窗口背后材质，离屏快照无法呈现，仅在真实窗口可见。
- 侧栏底部状态按钮改为仅下载时出现的进度环；数量徽标移到「下载」图标上。
- 历史页改名「书架」，记录新增可选 `coverURL`；旧记录无封面时显示首字封面。

## 结果

- 版本 `1.12.0`，已构建并替换 `/Applications/MangaGlass.app`。
- `swift test` 38 项通过（2 项按设计跳过）；快照覆盖 3 主题 × 浅/深 的首页、下载、书架、设置，人工核对通过。
