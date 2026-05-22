# ExecPlan：章节选择交互优化

## 摘要

本次要优化主界面“分类 / 章节”区域，让大量章节场景下的选择、批量操作和加入队列更明确、更少误触。实现范围限定在选择呈现与反馈，不改变解析、下载队列、排序、点击选择、Cmd 多选和拖拽框选算法。

## 用户价值

- 用户可以在顶部直接看到“已选 / 可见”数量，减少判断成本。
- 分类 chip 和分类 section 都显示已选数量，方便大量分类下确认选择范围。
- 滚动到列表中部时仍能通过底部浮条清空选择或加入队列。
- 章节卡片选中态、hover、tooltip 更清楚，长标题更容易确认。

## 范围

范围内：

- 重组章节面板顶部工具条。
- 优化分类选择条与分类 section 操作文案。
- 增加章节选择摘要浮条。
- 补充 `MainViewModel` 只读选择统计 helper。
- 更新版本号到 `1.2.10`。

范围外：

- 不改下载队列模型和 `startDownload()` 的选择语义。
- 不改解析、网络、持久化、并发逻辑。
- 不改拖拽框选、点击选择、Shift/Cmd 多选算法。

## 约束

- 必须复用当前设计系统和四套皮肤能力。
- 选择摘要浮条只在章节面板内部显示，不覆盖下载底栏。
- 本次属于普通用户可见 UI/交互优化，按版本规则递增补丁版本，目标版本为 `1.2.10`。

## 修改文件

- `Sources/MangaGlass/App/MainViewModel.swift`
- `Sources/MangaGlass/UI/ContentView.swift`
- `scripts/build_app.sh`
- `scripts/build_dmg.sh`
- `docs/execplans/chapter-selection-ux.md`

## 已确认事实

- `selectAllVisible()`、`deselectAllVisible()`、`toggleVolumeChapterSelection()` 和 `selectedChapterCount(in:)` 已存在于 `MainViewModel`。
- `ChapterChip` 已有选中图标、选中底色和左侧强调条，但缺少 tooltip。
- 章节面板顶部目前在窄/宽布局中分别重复放置“全选 / 清空 / 加入队列”。
- `requestStartDownload()` 已在未选择章节时弹出“加入全部可见章节？”确认，计划复用该逻辑。

## 实施计划

### 里程碑 1：选择统计 helper

- 在 `MainViewModel` 增加可见章节总数、当前可见已选数量、分类是否部分选中的只读 helper。
- 可观察结果：UI 可以稳定显示 `已选 X / 可见 Y` 和每个分类的 `已选/总数`。

### 里程碑 2：章节工具条与分类条

- 重组 `chapterPanel` 顶部为选择工具条。
- 分类 chip 改为显示 `分类名 · 已选/总数`。
- 分类批量按钮改名为 `全选分类` / `清空分类`。

### 里程碑 3：分类 section 与章节 chip

- section 操作按钮按未选/部分/全选显示 `选择本组` / `补全本组` / `清空本组`。
- `ChapterChip` 增加完整章节名和分类名 tooltip。

### 里程碑 4：选择摘要浮条

- 当已选章节数大于 0 时，在章节滚动区底部显示浮条。
- 浮条提供 `已选 X 话`、`清空`、`加入队列`。

### 里程碑 5：版本与验证

- 更新构建脚本版本号到 `1.2.10`。
- 运行 `swift build`。
- 更新本 ExecPlan 的进度、决策、意外发现和结果。

## 验证方式

- `swift build`
- 静态检查目标文案和版本号。
- 手动验收：多分类漫画下切换分类、全选/清空分类、单击/Cmd/拖拽选择、顶部和浮条加入队列、窄窗口布局。

## 风险

- 顶部工具条在窄窗口下可能挤压，需要用换行布局保守处理。
- 浮条不能截获滚动区正常点击和拖拽。
- 分类 chip 文案变长后需要 `lineLimit` 和 `minimumScaleFactor` 保证不撑破。

## 决策记录

- 决策：复用现有 `requestStartDownload()` 处理未选择时的加入全部可见确认。
  原因：计划要求保持现有二次确认和下载语义。

- 决策：本次版本目标为 `1.2.10`。
  原因：当前应用版本为 `1.2.9`，本次是用户可见 UI/交互优化。

- 决策：顶部工具条在窄/宽布局中使用同一套垂直结构，而不是分别维护两套按钮布局。
  原因：避免窄/宽布局文案和行为漂移，降低后续维护成本。

- 决策：选择摘要浮条放在章节滚动区的 `ZStack` 底部，并为列表内容增加底部 padding。
  原因：确保浮条不覆盖下载底栏，同时减少遮挡最后一行章节的概率。

- 决策：将“可见”文案统一替换为“全部/共”，并且顶部 `加入全部` 仅在没有选中章节时显示，版本递增到 `1.2.11`。
  原因：用户认为“可见”命名不自然，并选择只在底部浮条保留已选章节的 `加入队列`。

## 进度

- [x] 创建并保存 ExecPlan。
- [x] 完成主要实现。
- [x] 完成验证。

## 意外发现

- `ChapterChip` 已经具备左侧强调条，本次只需增强 tooltip 与上下游选择反馈。
- `chapterPanel` 原先在窄/宽布局中重复维护顶部按钮，本次合并为统一工具条。

## 结果与回顾

- 已在 `MainViewModel` 增加可见章节数、可见已选数和分类部分选中判断 helper。
- 已将章节面板顶部重组为统一选择工具条，显示 `已选 X / 可见 Y`，并区分 `加入队列` 与 `加入全部可见`。
- 已将分类条按钮改为 `全选分类` / `清空分类`，分类 chip 显示 `已选/总数` 并提供 tooltip。
- 已将分类 section 操作改为 `选择本组` / `补全本组` / `清空本组`。
- 已增加章节选择摘要浮条，选中章节后可在滚动区底部直接清空或加入队列。
- 已给章节 chip 增加完整章节名与分类名 tooltip。
- 已将构建脚本版本更新为 `1.2.10`。
- 已将“可见”相关文案调整为 `共`、`全选`、`加入全部`，并移除选中后顶部 `加入队列` 入口。
- 验证通过：`swift build` 成功。
- 验证通过：目标文案、helper 和版本号均可通过 `rg` 静态检查定位。
- 验证通过：`./scripts/build_app.sh --install` 成功安装到 `/Applications/MangaGlass.app`。
- 验证通过：`/Applications/MangaGlass.app/Contents/Info.plist` 中 `CFBundleShortVersionString` 与 `CFBundleVersion` 均为 `1.2.10`。
- 验证通过：文案和入口取舍调整后，`swift build` 成功。
- 验证通过：`rg -n "可见|全选可见|加入全部可见|addToQueueTitle|已选 .* / 共|Button\\(\\\"全选\\\"|Button\\(\\\"加入全部\\\"|APP_VERSION" Sources/MangaGlass scripts/build_app.sh scripts/build_dmg.sh` 显示旧文案/helper 已移除，目标文案和 `1.2.11` 版本号存在。
- 验证通过：`./scripts/build_app.sh --install` 成功安装到 `/Applications/MangaGlass.app`。
- 验证通过：`/Applications/MangaGlass.app/Contents/Info.plist` 中 `CFBundleShortVersionString` 与 `CFBundleVersion` 均为 `1.2.11`。
- 剩余风险：本轮未做截图级视觉验收；窄窗口下仍建议实际打开应用检查按钮是否在极小宽度下换行舒适。
