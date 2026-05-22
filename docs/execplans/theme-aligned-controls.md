# ExecPlan：统一主题化按钮与排序控件

## 摘要

本次任务要修复章节面板里“正序 / 倒序”排序控件的字体和配色与应用主题割裂的问题，并顺手排查其他类似的自绘按钮或系统样式控件，优先把同一类控件沉淀到 `DesignSystem.swift` 中复用。

目标是让章节排序、下载管理筛选、分类选择等小型分段/胶囊控件在浅色和深色主题下使用一致的字体、填充、描边、选中态和 hover/pressed 反馈，同时保持现有交互行为不变。

## 用户价值

- 用户在章节排序时看到的“正序 / 倒序”控件会和主界面的按钮、状态胶囊保持同一视觉语言。
- 其他同类按钮不再各自硬编码颜色，后续主题调整可以集中修改。
- 保持现有排序、筛选、分类选择、下载控制行为，不引入新的操作路径。

## 范围

范围内：

- 替换章节面板 `sortPicker` 的系统 segmented picker 外观，使用主题化自定义分段控件。
- 排查并统一下载管理器中的筛选按钮视觉样式。
- 评估分类选择 strip 中的胶囊按钮是否需要接入同一主题 helper。
- 在 `DesignSystem.swift` 增加可复用的小型选择控件样式或 helper。
- 将应用版本从 `1.2.1` 递增到 `1.2.2`。

范围外：

- 不改变章节排序逻辑、下载队列逻辑、网络请求或持久化行为。
- 不进行整页视觉重构，不调整布局结构之外的主流程。
- 不修改 `dist/` 构建产物，除非验证命令或用户明确要求重新打包。

## 约束

- 必须遵循项目已有设计系统：`MGTheme`、`MGFont`、`MGSpacing`、`MGActionButtonStyle`、`mgStatusPill`。
- 本次先按普通用户可见 UI 修复将版本递增到 `1.2.2`；随后同步完整主题样式能力，目标版本更新为 `1.2.3`。
- 不回滚工作区中既有 `.build/` 等生成物改动；它们与本任务无关。
- SwiftUI 控件需要兼容 macOS 13。

## 修改文件

- `Sources/MangaGlass/UI/DesignSystem.swift`
- `Sources/MangaGlass/UI/ContentView.swift`
- `Sources/MangaGlass/UI/DownloadManagerView.swift`
- `scripts/build_app.sh`
- `scripts/build_dmg.sh`
- `docs/execplans/theme-aligned-controls.md`

## 已确认事实

- `SortDirection` 的展示文案为 `正序` 和 `倒序`，定义在 `Sources/MangaGlass/App/MainViewModel.swift`。
- 章节面板的排序控件位于 `Sources/MangaGlass/UI/ContentView.swift` 的 `sortPicker(width:)`，当前使用 `.pickerStyle(.segmented)`。
- 项目已有 `MGTheme`、`MGFont` 和 `MGActionButtonStyle`，多数普通按钮已使用主题样式。
- 下载管理器筛选按钮在 `Sources/MangaGlass/UI/DownloadManagerView.swift` 中自绘，使用了硬编码 `Color.white.opacity(0.24)` 和 `MGTheme.accentStrong`。
- `scripts/build_app.sh` 和 `scripts/build_dmg.sh` 当前 `APP_VERSION` 均为 `1.2.1`。
- 用户反馈安装后的应用只剩浅色/深色主题模式，当前源码确实缺少主题色选择入口和主题色持久化。

## 实施计划

### 里程碑 1：沉淀主题化选择控件

- 在 `DesignSystem.swift` 增加适合“正序 / 倒序”和下载筛选使用的小型主题化选择按钮样式。
- 可观察结果：选中态、未选中态、hover、pressed、禁用态都来自 `MGTheme` 和 `MGFont`。

### 里程碑 2：替换章节排序控件

- 将 `sortPicker(width:)` 从系统 segmented picker 改成自定义主题化双按钮控件。
- 可观察结果：“正序 / 倒序”字体使用 `MGFont`，配色跟随浅色/深色主题，宽度仍由 `LayoutMetrics.sortControlWidth` 控制。

### 里程碑 3：统一其他类似按钮

- 将下载管理器筛选按钮改用相同主题 helper。
- 检查分类选择 strip 的胶囊按钮，必要时去掉重复 padding 或改用同一主题风格。
- 可观察结果：下载筛选和章节排序的选中/未选中态一致，不再出现孤立的硬编码白色选中层。

### 里程碑 4：版本与验证

- 将两个构建脚本的 `APP_VERSION` 更新到 `1.2.2`。
- 运行 Swift 构建验证。
- 更新本 ExecPlan 的进度、决策、意外发现、结果与回顾。

### 里程碑 5：恢复主题色选择

- 增加可持久化的主题色枚举，并让 `MGTheme` 的强调色族跟随该选择。
- 在“主题”菜单里恢复“主题色”选择入口。
- 可观察结果：用户可以在系统/浅色/暗黑之外选择主题色，排序控件和同类按钮跟随新主题色变化。

## 验证方式

- `swift build`
- 静态检查相关 UI 文件中剩余的疑似硬编码按钮样式。
- 用户可观察验收：
  - 主界面章节面板的“正序 / 倒序”控件与主题一致。
  - 下载管理器顶部筛选按钮与排序控件风格一致。
  - 浅色和深色模式下文字可读、选中态明确、布局不跳动。

## 风险

- 自定义替代 `Picker` 后需要确保点击区域、绑定更新和键盘/辅助功能标签仍清晰。
- 下载筛选按钮包含数量角标，复用样式时要避免文本挤压。
- 过度统一可能让特殊状态不够醒目，需要保留失败、警告等状态色。

## 决策记录

- 决策：本次按普通 UI 修复处理，版本目标为 `1.2.2`。
  原因：修改会改变用户可见界面，但不涉及新增主要功能或架构调整。

- 决策：先创建 ExecPlan，不直接修改实现代码。
  原因：任务涉及多个 UI 文件和设计系统，符合项目复杂任务规则。

- 决策：新增 `MGSelectionButtonStyle` 和 `mgSegmentContainer`，用它们覆盖排序控件与下载筛选按钮。
  原因：问题集中在小型选项按钮没有复用主题字体、填充和描边；沉淀为设计系统能力能避免同类问题继续分散。

- 决策：保留分类选择 strip 当前的 `mgStatusPill` 风格，不在本次重写。
  原因：该处已经使用主题 helper，和排序控件的割裂来源不同；本次只去掉明显自绘或系统默认外观的同类问题。

- 决策：将主界面内联统计胶囊的固定白色底色改为 `MGTheme.insetFill`。
  原因：它不是按钮，但属于同一组顶部小控件视觉语言，固定白色透明度在深浅主题下容易产生割裂。

- 决策：补回 `MGThemeAccent` 和 `MainViewModel.themeAccent`，并由 `MGTheme` 读取持久化主题色。
  原因：重新安装的应用暴露出当前源码缺少主题色选择，必须让主题色成为设计系统的一等输入，而不是只保留浅色/深色模式。

- 决策：采用 `/Users/mraz/.gemini/antigravity/worktrees/mangaglass/optimize-ui-style-design` 中的 `AppColorTheme` 完整主题设计，替换临时 `MGThemeAccent` 简单色板。
  原因：用户明确指出刚才设计的主题路径在 Antigravity worktree 中；该版本包含完整颜色、字体、圆角、面板、描边和阴影设计，应该作为现有 gitlab 版本的真实主题来源。

- 决策：保留二级菜单结构，组织为 `主题 -> 外观模式 / 主题配色`。
  原因：用户认可二级菜单设计，新的完整主题样式功能也应放入同一层级，避免顶层菜单继续膨胀。

- 决策：本轮完整主题样式同步后将应用版本递增到 `1.2.3`。
  原因：这是新的用户可见样式能力，不再只是 `1.2.2` 的小修补。

- 决策：将外观菜单调整为 `外观 -> 主题模式 / 皮肤`，并将四套皮肤名简化为 `经典`、`工业`、`书卷`、`江南`。
  原因：用户希望皮肤和浅色/深色主题模式分开，入口更直观，不使用复杂长命名。

- 决策：退出确认弹窗在展示前按当前主窗口中心重新定位。
  原因：应用级 `NSAlert.runModal()` 默认位置会显得偏，用户期望弹出框落在窗口中间。

- 决策：本轮菜单命名和弹窗位置调整后将版本递增到 `1.2.4`。
  原因：这是用户可见 UI 行为和文案调整，按项目规则递增补丁版本。

- 决策：将退出确认从系统 `NSAlert` 改为应用内 overlay，并将版本递增到 `1.2.5`。
  原因：用户希望弹窗位于 app 页面中间偏上，而不是系统级窗口；这是用户可见交互行为变化。

- 决策：将退出确认 overlay 改为实体卡片背景，并将位置从中间偏上调整为更接近页面中心；同时优化下载管理器“更多”菜单，并将版本递增到 `1.2.6`。
  原因：用户希望保留卡片质感而不是透明浮层，并要求按前述思路优化“更多”按钮内容。

- 决策：将应用内退出确认卡片视觉调整为接近 macOS 系统 `NSAlert`，并将版本递增到 `1.2.7`。
  原因：用户希望保留 app 内位置，但卡片样式“一模一样”接近刚才系统级 alert。

- 决策：重新设计退出确认为非透明高级 Apple 风格实体卡片，并将版本递增到 `1.2.8`。
  原因：用户不满意系统 alert 复刻效果，希望改为新的高级 Apple 风格且明确不要透明。

- 决策：将退出确认卡片整体缩小，并将版本递增到 `1.2.9`。
  原因：用户反馈卡片设计太大，需要更轻量的确认面板。

## 进度

- [x] 创建并保存 ExecPlan。
- [x] 完成主要实现。
- [x] 完成验证。

## 意外发现

- 下载管理器筛选按钮同样存在自绘选中态，虽然部分使用了 `MGTheme`，但字体和选中背景没有通过统一样式约束。
- 主界面内联统计胶囊也有固定 `Color.white.opacity` 背景，已改为主题 inset 填充。
- 当前源码只有 `AppThemeMode`，没有主题色切换；安装 release 包会覆盖之前 `/Applications` 中可能存在的手工主题色版本。
- 外部 Antigravity worktree 的真实项目目录是 `/Users/mraz/.gemini/antigravity/worktrees/mangaglass/optimize-ui-style-design`。
- 外部主题系统使用持久化 key `colorTheme` 和四套 `AppColorTheme`：`classicBlue`、`nordicAurora`、`champagneLuxury`、`cyberNeon`。
- 退出确认使用 `AppDelegate.requestTerminationConfirmation()` 中的 `NSAlert.runModal()`。
- 退出确认路径现在由 `AppDelegate` 发起请求，`MainViewModel` 保存确认状态，`ContentView` 渲染应用内 overlay。

## 结果与回顾

- 已在 `DesignSystem.swift` 增加 `MGSelectionButtonStyle` 和 `mgSegmentContainer`，用于统一小型分段/选择按钮的字体、选中态、未选中态、hover、pressed、描边和主题填充。
- 已将章节面板“正序 / 倒序”从系统 `.segmented` picker 改为主题化双按钮控件，保留 `chapterSortDirection` 绑定和原有排序行为。
- 已将下载管理器顶部筛选按钮改用同一主题选择按钮样式，数量角标仍保留但背景跟随主题。
- 已将主界面内联统计胶囊从固定白色透明背景改为 `MGTheme.insetFill`。
- 已新增主题色选择与持久化，`MGTheme.accent`、`accentStrong`、`accentSoft`、`cyanAction` 会跟随所选主题色变化。
- 已在“主题”菜单中加入“主题色”子菜单。
- 已将主题系统进一步同步为 Antigravity worktree 中的完整 `AppColorTheme` 设计，并保留本轮新增的主题化排序/筛选按钮样式。
- 已将“主题”菜单组织为二级菜单：`外观模式` 与 `主题配色`。
- 已将外观菜单改为 `外观 -> 主题模式 / 皮肤`，并简化四套皮肤显示名。
- 已让退出确认弹窗优先按当前主窗口居中。
- 已将退出确认从系统弹窗改为 app 内页面 overlay，位置在内容区域中间偏上，支持点击遮罩或取消按钮关闭。
- 已将退出确认 overlay 的卡片背景改为实体面板，位置调整为页面中部略偏上。
- 已将下载管理器“更多”菜单整理为 `下载操作`、`风控处理`、`管理`、`危险操作` 分组，按当前任务状态动态显示可用动作。
- 已将退出确认 overlay 的视觉改为系统 alert 风格：警告图标、紧凑宽度、原生按钮、浅灰/深灰实体背景。
- 已重新设计退出确认 overlay：实体圆角卡片、居中排版、电源图标容器、等宽操作按钮，不使用透明卡片背景。
- 已缩小退出确认卡片的宽度、内边距、图标尺寸、标题字号、按钮间距和阴影。
- 已将 `scripts/build_app.sh` 和 `scripts/build_dmg.sh` 的 `APP_VERSION` 更新为 `1.2.4`。
- 验证通过：`swift build` 成功，包括补回主题色选择后的二次构建。
- 验证通过：`rg -n "pickerStyle\\(\\.segmented\\)|Color\\.white\\.opacity\\(0\\.24\\)|filter == type \\?" Sources/MangaGlass/UI` 无匹配结果。
- 验证通过：`rg -n "MGThemeAccent|themeAccent|APP_VERSION=|AppColorTheme|主题配色|外观模式|MGSelectionButtonStyle|mgSegmentContainer" Sources/MangaGlass scripts/build_app.sh scripts/build_dmg.sh` 能看到 `AppColorTheme`、二级菜单和主题化选择控件，且旧临时主题色类型无匹配。
- 验证通过：`./scripts/build_app.sh --install` 成功生成 `dist/MangaGlass.app` 并安装到 `/Applications/MangaGlass.app`；同步 Antigravity 主题设计后已重新安装 `1.2.3`。
- 验证通过：`/Applications/MangaGlass.app/Contents/Info.plist` 中 `CFBundleShortVersionString` 与 `CFBundleVersion` 均为 `1.2.3`。
- 验证通过：菜单命名和退出弹窗位置调整后，`swift build` 继续成功。
- 验证通过：`rg -n "APP_VERSION=|Menu\\(\\\"外观\\\"\\)|Menu\\(\\\"主题模式\\\"\\)|Menu\\(\\\"皮肤\\\"\\)|case \\.classicBlue: return \\\"经典\\\"|case \\.nordicAurora: return \\\"工业\\\"|case \\.champagneLuxury: return \\\"书卷\\\"|case \\.cyberNeon: return \\\"江南\\\"|centerAlertWindow" Sources/MangaGlass scripts/build_app.sh scripts/build_dmg.sh` 能看到目标入口、简化皮肤名、弹窗居中 helper 和 `1.2.4` 版本号。
- 验证通过：`./scripts/build_app.sh --install` 成功安装 `1.2.4` 到 `/Applications/MangaGlass.app`。
- 验证通过：`/Applications/MangaGlass.app/Contents/Info.plist` 中 `CFBundleShortVersionString` 与 `CFBundleVersion` 均为 `1.2.4`。
- 验证通过：应用内退出确认 overlay 改造后，`swift build` 成功。
- 验证通过：`rg -n "APP_VERSION=|NSAlert|terminationConfirmation|presentTerminationConfirmation|Menu\\(\\\"外观\\\"\\)|Menu\\(\\\"皮肤\\\"\\)" Sources/MangaGlass scripts/build_app.sh scripts/build_dmg.sh` 能看到 `1.2.5`、应用内退出状态与菜单入口，且退出路径不再包含 `NSAlert`。
- 验证通过：`./scripts/build_app.sh --install` 成功安装 `1.2.5` 到 `/Applications/MangaGlass.app`。
- 验证通过：`/Applications/MangaGlass.app/Contents/Info.plist` 中 `CFBundleShortVersionString` 与 `CFBundleVersion` 均为 `1.2.5`。
- 验证通过：退出卡片和“更多”菜单优化后，`swift build` 成功。
- 验证通过：`rg -n "下载操作|风控处理|危险操作|取消并清空队列|清空全部记录|settingsBackgroundFill|size.height \\* 0\\.30" Sources/MangaGlass` 能看到目标菜单分组与实体卡片定位。
- 验证通过：`./scripts/build_app.sh --install` 成功安装 `1.2.6` 到 `/Applications/MangaGlass.app`。
- 验证通过：`/Applications/MangaGlass.app/Contents/Info.plist` 中 `CFBundleShortVersionString` 与 `CFBundleVersion` 均为 `1.2.6`。
- 验证通过：系统 alert 风格调整后，`swift build` 成功。
- 验证通过：`./scripts/build_app.sh --install` 成功安装 `1.2.7` 到 `/Applications/MangaGlass.app`。
- 验证通过：`/Applications/MangaGlass.app/Contents/Info.plist` 中 `CFBundleShortVersionString` 与 `CFBundleVersion` 均为 `1.2.7`。
- 验证通过：新版 Apple 风格退出卡片调整后，`swift build` 成功。
- 验证通过：`./scripts/build_app.sh --install` 成功安装 `1.2.8` 到 `/Applications/MangaGlass.app`。
- 验证通过：`/Applications/MangaGlass.app/Contents/Info.plist` 中 `CFBundleShortVersionString` 与 `CFBundleVersion` 均为 `1.2.8`。
- 验证通过：缩小退出卡片后，`swift build` 成功。
- 验证通过：`./scripts/build_app.sh --install` 成功安装 `1.2.9` 到 `/Applications/MangaGlass.app`。
- 验证通过：`/Applications/MangaGlass.app/Contents/Info.plist` 中 `CFBundleShortVersionString` 与 `CFBundleVersion` 均为 `1.2.9`。
- 剩余风险：本轮未做截图级视觉验收；当前通过代码审查和编译安装确认样式入口已统一，实际观感可在已安装应用中查看。
