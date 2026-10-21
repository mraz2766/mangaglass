# ExecPlan：按苹果 macOS 设计规范（HIG）优化界面

## 摘要

对照 Apple Human Interface Guidelines（Designing for macOS、Sidebars、Toolbars、Materials、Windows、Typography），在保留「沉浸封面」风格的前提下，让应用更像原生 Mac 应用。用户已确认范围：设置改独立窗口、标题栏保持空白、强调色可选跟随系统、系统字号、经典主题玻璃收敛、细节统一。不做菜单栏快捷键扩展。只改界面，不动下载与解析逻辑。

## 规范依据 → 改动

| HIG 要点 | 现状 | 改动 |
|---|---|---|
| 设置放在独立窗口，⌘, 打开 | 设置是侧栏页 | 新增 `Settings` 场景，分「通用 / 下载 / 账户与站点」标签，原生分组表单；侧栏只留 首页 / 下载 / 书架 |
| 标题栏：没有有用标题时可留空（如备忘录） | 已留空 | 保持 |
| 侧栏图标应体现用户选择的系统强调色 | 每个主题固定强调色 | 设置「通用」新增开关「跟随系统强调色」，默认关；开启后强调色、经典主题的选中色改用 `controlAccentColor` |
| 用系统文字样式，正文 13pt，最小不低于 10pt | 全部写死字号，角标 9pt | `MGFont` 改用系统文字样式；散落的固定字号改为文字样式；角标提升到 10pt。展示型大数字（百分比、横幅标题）保留显式字号 |
| Liquid Glass/玻璃只用于控件与导航层，不用于内容层 | 经典主题整窗玻璃，内容卡片半透明 | 经典主题：玻璃只在侧栏；内容画布与卡片改为不透明白/深灰；吸顶分组标题改用画布色 |
| 一致的间距与层级 | 圆角 6/8/10/12/14/16/18 混用 | 新增 `MGRadius`（control 6、small 8、card 12、hero 16），设置卡片 14→12 |

## 文字样式映射

| 旧 | 新 |
|---|---|
| title 22 semibold | `.title` semibold |
| section / appTitle 14 semibold | `.title3` semibold（15） |
| body 13 / bodyStrong | `.body` / `.body` medium |
| caption 12 / captionStrong | `.callout` / `.callout` medium |
| mono 11 / number 12 | `.subheadline` / `.callout` 等宽 |
| 页面大标题 22 bold | `.title` bold |
| 横幅标题 28 | `.largeTitle` bold |

## 约束

- 大幅度修改：`1.15.2` → `1.16.0`。
- 设置窗口与主窗口共用同一个 `MainViewModel`，主题/外观改动两边同时生效。
- macOS 13 兼容：`Settings` 场景自 macOS 13 可用，无需代码打开设置窗口。
- 不改 1.15.x 的窗口修复（只写变化的属性、透明标题栏）。

## 进度

- [x] 设置窗口 + 侧栏去设置项
- [x] 跟随系统强调色
- [x] 系统文字样式
- [x] 经典主题玻璃收敛
- [x] 圆角统一
- [x] 测试、快照核对、真实运行
- [x] 版本、构建、提交

## 决策记录

- 设置窗口用 SwiftUI `Settings` 场景，菜单「MangaGlass › 设置…」和 ⌘, 由系统自动提供；未保留应用内入口（用户选择侧栏只留三项）。
- `AppDelegate.isAppContentWindow` 排除标识含 "settings" 的窗口，避免设置窗口被套用主窗口样式、最小尺寸和关闭行为。
- 跟随系统强调色：只替换强调色；经典主题（选中色本就是强调色，`accentSelects`）同时替换选中色。墨与纸、石墨的墨色/紫灰选中保持主题特色。重建标识由 `themeStyle` 扩展为 `appearanceID`。
- 经典主题：画布与卡片改为不透明（浅 #F5F6F8 / 白，深 #1D1D1F / #2A2A2C），玻璃只铺在侧栏；浮动的选择胶囊和恢复横幅仍用材质（属于浮在内容上的控件层）。
- 字号：文字统一走系统文字样式；图标字形、下载页 44pt 百分比等展示型数字保留显式尺寸。侧栏角标 9pt → 10pt。
- 设置文件拆分：`HistoryAndSettingsWorkspace.swift` → `HistoryWorkspaceView.swift` + `UI/SettingsView.swift`。

## 结果

- 版本 `1.16.0`；`swift test` 72 项通过（3 项按设计跳过）；快照新增设置窗口（主题色 / 系统强调色 × 浅 / 深）。
- 真实运行：菜单「设置…」打开独立窗口，「通用 / 下载 / 账户与站点」标签切换正常；主窗口侧栏三项可点。
- README 双语同步：设置入口、强调色选项、经典主题描述、版本徽章。
