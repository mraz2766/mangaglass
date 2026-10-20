# ExecPlan：可选主题「墨与纸」「石墨」

## 摘要

用户从三张方向草图中选定 A（墨与纸）和 C（石墨），要求两者都作为可选主题。保留现有外观为「经典」，新增「主题」设置，与已有的「外观（跟随系统/浅色/暗黑）」正交：每个主题都有浅色与深色两套色值。只改视觉，不改业务逻辑。

## 用户价值

- 设置里一键切换三种风格，不满意随时回到经典。
- 墨与纸：暖白纸面、墨色选中块、唯一的朱红主操作，章节号放大。
- 石墨：深灰分层、紫色只用于选中和主操作，专业工具感。

## 设计

- `AppThemeStyle`：`classic` / `ink` / `graphite`，持久化键 `themeStyle`，默认 `ink`。
- `MGPalette`：每个主题一组动态 `NSColor`（按 NSAppearance 自动解析浅/深），字段：画布、侧栏、卡片/格子底、分隔线、强调色、选中底/字/描边、强调按钮底/字、正文色。
- `MGTheme` 现有接口改为读当前主题调色板，调用方基本不改。
- 新增按钮变体 `.emphasis`：「解析」等次主操作用墨色/石墨灰，避免一屏两个强调色按钮。
- 章节格：新主题下「第 N 话」拆为大号数字 + 小号「话」；无法解析的标题原样显示。
- 切换主题时用 `.id(themeStyle)` 重建工作区，保证不观察 vm 的子视图也刷新。

| 令牌 | 墨与纸 浅 / 深 | 石墨 浅 / 深 |
|---|---|---|
| 画布 | `#F7F5F0` / `#1C1B19` | `#F5F5F7` / `#18181A` |
| 侧栏 | `#EFECE4` / `#161513` | `#EBEBEE` / `#111113` |
| 格子 | `#FFFFFF` / `#262522` | `#FFFFFF` / `#222225` |
| 正文 | `#2C2C2A` / `#EDEBE4` | `#1C1C1E` / `#EDEDED` |
| 强调 | `#D85A30` / `#E8774F` | `#534AB7` / `#7F77DD` |
| 选中底 | `#2C2C2A` / `#EDEBE4` | `#EEEDFE` / `#3C3489` |

## 范围

- 范围内：`MainViewModel.swift`（主题枚举与持久化）、`DesignSystem.swift`、`ContentView.swift`、`WorkspaceChrome.swift`、`DownloadWorkspaceView.swift`、`HistoryAndSettingsWorkspace.swift`、`LayoutSnapshots.swift`。
- 范围外：布局结构、业务逻辑、性能。

## 约束

- 显著 UI 改动：版本 `1.10.0` → `1.11.0`。
- macOS 13 API；构建后替换 `/Applications/MangaGlass.app`；中文 `feat:` 提交。

## 验证

- `swift test`；`LayoutSnapshots` 渲染 3 主题 × 浅/深，人工核对对比度与层级。
- `scripts/build_app.sh --install`。

## 决策记录

- 默认主题设为「墨与纸」：用户明确认为原外观不够现代；「经典」保留为一键回退。
- 主题状态用全局 `MGTheme.style`（`nonisolated(unsafe)`），由 vm `didSet` 写入；侧栏与工作区挂 `.id(themeStyle)` 强制重建，避免不观察 vm 的视图（队列页、等值化的章节网格）残留旧色。
- 侧栏导航、队列筛选用「弱选中」色（浅底 + 正文/强调字），章节格用「强选中」色（墨块/紫块），避免侧栏出现大色块。
- 快照测试中 vm 初始化会按 UserDefaults 覆盖主题，测试改为通过 `vm.themeStyle` 设置。

## 结果

- 版本 `1.11.0`，已构建并替换 `/Applications/MangaGlass.app`。
- `swift test` 通过；`LayoutSnapshots` 渲染 3 主题 × 浅/深 的首页、队列、历史、设置，人工核对通过。
- 设置页新增「主题：经典 / 墨与纸 / 石墨」，与「外观」独立组合。
