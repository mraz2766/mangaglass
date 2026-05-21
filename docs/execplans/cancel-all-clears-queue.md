# ExecPlan：取消所有时清空下载队列

## 摘要

修正下载管理器中“取消所有”的行为：确认后不再把所有排队/运行任务标记为取消并留在失败列表，而是中止当前下载、清空队列和下载状态。

本次属于普通修改，按版本规则从 `1.2.0` 递增到 `1.2.1`。不改变单条取消行为；单条取消仍可保留取消状态用于用户识别。

## 用户价值

- 点击“取消所有”后，下载管理器不再出现一堆失败/取消记录。
- 用户明确确认后，当前下载状态、队列、进度和软熔断提示都会清空，界面回到干净状态。
- 已下载到本地的文件不会被删除。

## 范围

范围内：

- 增加“取消并清空全部队列”的下载协调器方法。
- 下载管理器“取消所有”确认后调用新清空式取消路径。
- 调整确认弹窗标题、按钮和说明文案。
- 将 app 版本从 `1.2.0` 更新为 `1.2.1`。

范围外：

- 不改变单条取消、单条重试行为。
- 不删除已经下载到本地的图片文件。
- 不改变“清空完成”的行为。

## 约束

- 遵守项目 `AGENTS.md`：复杂任务必须先创建持久 ExecPlan，并随实施更新。
- 本次属于普通修改，目标版本号为 `1.2.1`。
- 构建验证使用 `./scripts/build_app.sh`。

## 修改文件

- `Sources/MangaGlass/Services/DownloadCoordinator.swift`
- `Sources/MangaGlass/App/MainViewModel.swift`
- `Sources/MangaGlass/UI/DownloadManagerView.swift`
- `scripts/build_app.sh`
- `scripts/build_dmg.sh`
- `docs/execplans/cancel-all-clears-queue.md`

## 已确认事实

- 当前 `DownloadCoordinator.cancel()` 会把 `.queued` / `.running` 改为 `.canceled`。
- 下载管理器失败过滤会把 `.canceled` 和 `.failed` 都归入“失败”视图。
- 下载管理器已经有“取消所有”的确认弹窗，但确认后调用的是 `vm.cancelDownload()`。

## 实施计划

### 里程碑 1：保存计划

- 创建本 ExecPlan 文件。
- 可观察结果：计划文件记录行为口径和目标版本。

### 里程碑 2：新增清空式取消

- 在 `DownloadCoordinator` 中新增可在运行中调用的取消并清空方法。
- 方法负责取消 master task、恢复暂停门、清理刷新任务、释放防睡眠、清空队列状态。
- 可观察结果：调用后 `taskItems` 为空，进度和消息回到清空状态。

### 里程碑 3：接入下载管理器

- 在 `MainViewModel` 增加对应入口并记录日志/status。
- 下载管理器“取消所有”弹窗确认后调用新入口。
- “取消所有”在有队列记录时可用，运行中和未运行但有排队任务都能清空。
- 可观察结果：确认后列表为空，不再产生失败/取消记录。

### 里程碑 4：版本与验证

- 将构建脚本版本更新到 `1.2.1`。
- 运行构建并检查版本字段。

## 验证方式

- `git diff --check`
- `./scripts/build_app.sh`
- `plutil -p dist/MangaGlass.app/Contents/Info.plist | rg "CFBundleShortVersionString|CFBundleVersion"`
- 手动验收：
  - 有运行任务时点击“取消所有”，确认后列表清空。
  - 有排队但未运行任务时点击“取消所有”，确认后列表清空。
  - 取消弹窗选择“返回”时队列不变。
  - 单条取消仍只影响单条任务。

## 风险

- 运行中的图片请求可能已经写完当前文件后才响应取消；本次只保证队列和状态清空，不删除已下载文件。
- 清空状态会同时清掉最近完成目录入口，因为用户要求清空当前所有状态。

## 决策记录

- 决策：保留原 `cancel()` 语义给可能需要保留取消记录的调用，新建清空式取消方法给“取消所有”使用。
  原因：避免破坏单条取消或未来需要查看取消记录的场景。

## 进度

- [x] 创建并保存 ExecPlan。
- [x] 完成清空式取消逻辑。
- [x] 完成下载管理器接入。
- [x] 更新版本号。
- [x] 完成验证。

## 意外发现

- `clearQueueState()` 原先只在空闲时使用，没有显式清理 `isRunning`、`speedText`、最近下载目录和漫画柜软熔断；本次将这些状态纳入清空口径。

## 结果与回顾

- 已新增 `DownloadCoordinator.cancelAndClearAll()`，用于运行中取消并清空全部下载状态。
- 下载管理器“取消所有”确认后改为调用清空式取消，确认文案改为“取消并清空”。
- “取消所有”在有任务记录时可用，确认后 `taskItems` 清空，不再留下 `.canceled` 记录进入失败列表。
- 已将构建版本更新到 `1.2.1`。
- 已运行 `git diff --check`，无空白错误。
- 已运行 `./scripts/build_app.sh`，release 构建成功并生成 `dist/MangaGlass.app`。
- 已检查生成的 `Info.plist`，`CFBundleShortVersionString` 与 `CFBundleVersion` 均为 `1.2.1`。
