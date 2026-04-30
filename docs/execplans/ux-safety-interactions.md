# ExecPlan：交互保护与完成后行动入口

## 摘要

本次实现 6 个用户体验改进：退出保护升级、危险操作确认、下载完成后的行动入口、启动时恢复队列提醒、解析失败后的下一步操作、未选章节时加入全量队列确认。

实现保持现有解析、下载、队列持久化、主题、日志和镜像重试能力不变，只在关键操作前后补充确认、提示和快捷行动入口。

## 用户价值

- 用户点击窗口关闭、`Cmd+Q` 或系统退出时能明确知道应用会完全退出，且下载队列不会被无提示中断。
- 清缓存、清历史、取消所有、清空队列、未选章节加入全部可见章节等高影响操作不再容易误触。
- 下载完成后能直接打开下载目录或最近完成章节目录，减少去 Finder 手动寻找的成本。
- 应用重启后若恢复了未完成队列，用户能立即选择继续、查看或稍后处理。
- 解析失败后可以复制错误、打开日志、切换站点入口，失败状态有明确下一步。

## 范围

范围内：

- 调整 `MangaGlassApp`、`AppDelegate`、`ContentView`、`DownloadManagerView`、`MainViewModel`、`DownloadCoordinator`。
- 增加必要的 SwiftUI alert / confirmationDialog 和 AppKit `NSAlert`。
- 增加最近完成下载目录状态与打开目录方法。
- 更新本 ExecPlan 的进度、决策记录、意外发现、结果与回顾。

范围外：

- 不新增偏好设置。
- 不改变下载并发、解析逻辑或站点 API。
- 不给单条取消或单条重试增加确认。
- 不做自动化 UI 测试或菜单栏重构。

## 约束

- 必须使用中文文案。
- 必须保留 macOS 原生交互习惯，破坏性操作按钮使用明确的破坏性角色。
- `ContentView` 的 `MainViewModel` 需要提升到 `MangaGlassApp` 持有，避免 `AppDelegate` 和主视图看到不同状态。
- 构建验证使用 `./scripts/build_app.sh`。

## 修改文件

- `Sources/MangaGlass/App/MangaGlassApp.swift`
- `Sources/MangaGlass/App/AppDelegate.swift`
- `Sources/MangaGlass/App/MainViewModel.swift`
- `Sources/MangaGlass/Services/DownloadCoordinator.swift`
- `Sources/MangaGlass/UI/ContentView.swift`
- `Sources/MangaGlass/UI/DownloadManagerView.swift`
- `docs/execplans/ux-safety-interactions.md`

## 已确认事实

- `ContentView` 当前用 `@StateObject private var vm = MainViewModel()` 创建视图模型。
- `AppDelegate` 已实现窗口关闭确认，但没有读取下载队列，也没有覆盖 `Cmd+Q` 或系统菜单退出。
- `DownloadCoordinator.restoreQueue(_:)` 会将恢复的 running 任务改为 queued。
- `DownloadTaskItem` 保存了 `comic`、`chapter`、`destination`、`state`，可以计算章节输出目录。
- 主界面已有日志面板、站点入口 popover、镜像重试、下载管理器 sheet。

## 实施计划

### 里程碑 1：共享状态与退出保护

- 将 `MainViewModel` 提升到 `MangaGlassApp` 持有并传入 `ContentView`。
- 让 `AppDelegate` 持有弱引用，用统一逻辑处理窗口关闭和应用退出。
- 退出弹窗根据下载队列状态展示不同说明，并用防递归标记避免二次弹窗。

### 里程碑 2：危险操作与队列确认

- 为清缓存、清历史、取消所有、清空所有增加确认。
- 为未选章节时加入全部可见章节增加确认；已选章节继续直接加入。

### 里程碑 3：完成入口、恢复提醒与失败下一步

- 在下载完成时记录最近完成输出目录，并提供打开目录方法。
- 在底部下载状态区和下载管理器中显示打开目录入口。
- 启动恢复队列后弹出提示，提供继续下载、打开下载管理、稍后处理。
- 解析失败区域增加复制错误、打开日志、站点入口。

### 里程碑 4：验证与回顾

- 运行 `./scripts/build_app.sh` 验证 release 构建。
- 手动检查关键交互路径，并记录剩余风险。

## 验证方式

- 运行 `./scripts/build_app.sh`。
- 手动验证窗口 `x`、`Cmd+Q`、应用菜单退出确认文案。
- 手动验证危险操作取消与确认路径。
- 手动验证未选章节加入队列确认。
- 手动验证解析失败后的复制错误、日志、站点入口。
- 手动验证下载完成后的目录入口。
- 手动验证恢复队列提醒的三个动作。

## 风险

- `AppDelegate` 与 SwiftUI 状态桥接若时机不对，退出弹窗可能拿不到队列摘要；需要在窗口出现时注入 view model。
- 下载完成目录计算必须和现有 `DownloadCoordinator` 的目录规则一致，否则 Finder 可能打开父目录而不是章节目录。
- SwiftUI alert 组合较多，需要避免多个 alert 绑定冲突。

## 决策记录

- 决策：使用 `MangaGlassApp` 持有单例 `MainViewModel`。
  原因：退出确认需要 AppDelegate 读取同一份下载状态，且主视图也需要恢复提示。
- 决策：退出确认统一放在 `AppDelegate.applicationShouldTerminate(_:)` 与 `windowShouldClose(_:)` 共用的私有方法中。
  原因：窗口关闭、`Cmd+Q` 和系统退出菜单都会经过同一套确认文案，避免行为分叉。
- 决策：主界面和下载管理器分别使用本地确认枚举管理 alert。
  原因：确认弹窗的状态只影响各自视图，避免多个布尔值交叉触发。
- 决策：最近下载入口记录章节输出目录，无法取得时回退下载根目录。
  原因：用户通常想直接看到刚完成的章节，但回退可以保证入口始终可用。

## 进度

- [x] 创建并保存 ExecPlan。
- [x] 完成共享状态与退出保护。
- [x] 完成危险操作与队列确认。
- [x] 完成完成入口、恢复提醒与失败下一步。
- [x] 完成验证。

## 意外发现

- 仓库当前跟踪了 `.build` 下的 SwiftPM 产物，构建验证会让这些产物出现在 `git status` 中；本次代码实现不依赖这些产物。

## 结果与回顾

- 已完成 6 个交互改进：统一退出确认、危险操作确认、下载完成入口、启动恢复提醒、解析失败下一步、未选章节全量加入确认。
- `./scripts/build_app.sh` 已成功完成 release 构建，并生成 `dist/MangaGlass.app`。
- `plutil -lint dist/MangaGlass.app/Contents/Info.plist` 结果为 OK。
- 剩余风险：恢复队列提醒、退出确认和下载完成目录入口仍需要在真实 GUI 操作中做一次人工验收。
