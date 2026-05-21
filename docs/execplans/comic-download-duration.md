# ExecPlan：按漫画统计下载总耗时

## 摘要

为 MangaGlass 的下载队列增加“按漫画统计总耗时”的能力。同一本漫画在同一下载目录下的一组章节，从首个章节真正进入下载开始计时，到该组任务全部结束后停止计时；运行中则动态显示已耗时。

本次只增加时间记录、聚合摘要和界面展示，不改变下载并发、重试、软熔断、解析或文件写入逻辑。耗时数据跟随当前下载队列存在，清理任务时同步消失。

## 用户价值

- 用户可以看到每本漫画本轮下载到底花了多久，而不是只能看全局速度。
- 同时下载多本漫画时，耗时按漫画分开，便于判断哪本漫画慢或失败较多。
- 单话展开详情能看到该话耗时，排查慢章节更直接。

## 范围

范围内：

- 扩展 `DownloadTaskItem`，记录任务开始和结束时间。
- 在 `DownloadCoordinator` 中提供按漫画和下载目录聚合的耗时摘要。
- 在主界面底部下载条展示当前或最近漫画耗时。
- 在下载管理器 header/footer 展示漫画耗时摘要，并在任务详情展示单话耗时。
- 保持旧持久化队列兼容，缺失时间字段时自动为 `nil`。

范围外：

- 不新增历史报表或独立数据库。
- 不改变 Copy 漫画和漫画柜的下载调度策略。
- 不增加用户设置项。

## 约束

- 遵守项目 `AGENTS.md`：复杂任务必须使用持久 ExecPlan，并在实施中更新进度、决策记录、意外发现、结果与回顾。
- 新增文案使用中文。
- 耗时格式小于 1 小时为 `MM:SS`，大于等于 1 小时为 `HH:MM:SS`。
- 旧队列 JSON 不能因为新增字段而解码失败。

## 修改文件

- `Sources/MangaGlass/Models/MangaModels.swift`
- `Sources/MangaGlass/Services/DownloadCoordinator.swift`
- `Sources/MangaGlass/UI/ContentView.swift`
- `Sources/MangaGlass/UI/DownloadManagerView.swift`
- `docs/execplans/comic-download-duration.md`

## 已确认事实

- `DownloadTaskItem` 已经 `Codable` 并持久化在 `downloadQueue`，适合用可选字段做兼容扩展。
- 下载状态统一通过 `DownloadCoordinator.setState(_:for:)` 进入 `.running`、`.done`、`.failed`、`.canceled`。
- 漫画柜软熔断会把运行中的漫画柜任务改回 `.queued`，这种状态不应当结束计时。
- 主界面底部下载条位于 `ContentView.simplifiedDownloadPanel(metrics:)`。
- 下载管理器 header、footer 和任务展开行位于 `DownloadManagerView`。

## 实施计划

### 里程碑 1：任务时间字段

- 给 `DownloadTaskItem` 增加 `startedAt`、`finishedAt` 可选字段。
- 在 `setState` 中为 `.running` 首次记录开始时间，为终态记录结束时间。
- 可观察结果：任务开始后有开始时间，完成/失败/取消后有结束时间。

### 里程碑 2：按漫画聚合耗时

- 在 `DownloadCoordinator` 增加 `ComicDurationSummary` 和 `comicDurationSummaries()`。
- 聚合键使用 `comic.slug + destination.path`，统计总任务数、完成数、失败/取消数、运行中状态和耗时。
- 可观察结果：同一本漫画同一目录合并成一条摘要，不同漫画或目录分开。

### 里程碑 3：界面展示

- 主界面底部显示当前运行漫画或最近完成漫画的耗时。
- 下载管理器 header/footer 显示漫画耗时摘要和简短列表。
- 单话展开详情显示该话耗时。
- 可观察结果：下载过程中耗时递增，结束后停止。

### 里程碑 4：验证与回顾

- 运行构建命令。
- 记录验证结果和剩余风险。

## 验证方式

- `./scripts/build_app.sh`
- 手动验收场景：
  - 下载单本漫画多话，确认开始后耗时递增，完成后停止。
  - 同时下载多本漫画，确认按漫画分开计时。
  - 失败/取消任务计入本轮耗时，并显示失败/取消数量。
  - 恢复旧队列不崩溃，继续下载后开始计时。
  - 清空完成任务后，相关耗时摘要同步消失。

## 风险

- SwiftUI 视图直接用 `Date()` 聚合时，非下载状态变化不会每秒刷新；下载运行期间已有进度刷新任务会带动界面更新。
- 软熔断把运行任务退回 `.queued` 时不记录结束时间，符合“用户决定继续下载”的行为，但会让本轮耗时包含等待确认时间。

## 决策记录

- 决策：运行任务退回 `.queued` 时保留 `startedAt`，不写 `finishedAt`。
  原因：软熔断不是任务终止，用户确认后继续下载应视为同一轮。
- 决策：漫画耗时摘要只展示至少开始过的漫画。
  原因：未开始的排队任务没有可解释的耗时，显示 `00:00` 容易误导。

## 进度

- [x] 创建并保存 ExecPlan。
- [x] 完成任务时间字段。
- [x] 完成按漫画聚合耗时。
- [x] 完成界面展示。
- [x] 完成验证。

## 意外发现

- `DownloadCoordinator` 已有进度刷新任务，下载运行中会自然带动耗时文本刷新；下载完全静止时不额外启动计时器。

## 结果与回顾

- 已完成 `DownloadTaskItem.startedAt` / `finishedAt` 兼容扩展，并在状态进入运行和终态时记录时间。
- 已完成 `DownloadCoordinator.comicDurationSummaries()` 和单话 `durationText(for:)`，按 `comic.slug + destination.path` 聚合。
- 主界面底部会显示当前优先漫画耗时；下载管理器 header/footer 展示漫画耗时摘要，任务展开详情显示该话耗时。
- 已运行 `git diff --check`，无空白错误。
- 已运行 `./scripts/build_app.sh`，release 构建成功并生成 `dist/MangaGlass.app`。
