# ExecPlan：关闭窗口行为设置

## 摘要与范围

设置新增“关闭窗口时”：直接退出、留在后台、弹窗询问。默认弹窗询问，持久保存选择；后台模式保留窗口和下载任务，点击 Dock 图标恢复窗口。Command-Q／菜单退出仍表示完全退出并沿用确认。

## 约束与决策

- 普通功能变更，1.5.1 → 1.5.2，构建安装至 `/Applications/MangaGlass.app`，中文 feat 提交。
- 仅主窗口关闭应用此设置，子窗口／弹窗关闭不触发退出。
- 后台状态请求完整退出时先恢复主窗口，避免确认框隐藏。
- 不新增菜单栏常驻图标，不改变下载与队列格式。

## 修改文件

- `Sources/MangaGlass/App/AppDelegate.swift`
- `Sources/MangaGlass/App/MainViewModel.swift`
- `Sources/MangaGlass/Models/WindowCloseBehavior.swift`
- `Sources/MangaGlass/UI/Workspace/HistoryAndSettingsWorkspace.swift`
- `Tests/MangaGlassTests/WindowCloseBehaviorTests.swift`
- `scripts/build_app.sh`

## 实施与验证

- [x] 阅读模板并保存计划。
- [x] 持久化设置、窗口关闭分流和恢复。
- [x] 测试默认值／保存与兼容、后台恢复／确认流程；构建安装、版本核对和提交。

## 结果

- `swift test --scratch-path /tmp/mangaglass-fluid-build`：13 项通过，0 失败，另 1 项可选截图测试未启用。新增 3 项覆盖偏好默认值／各值读写／未知值回退、后台隐藏与恢复、队列保留、显式退出确认和子窗口关闭。
- `bash scripts/build_app.sh --install` 成功，已重启安装应用，两个 Bundle 版本均为 1.5.2。
- 实机选择留在后台后 Command-W，进程 PID 70787 保持；恢复窗口后仍处于原设置页面。选择直接退出后 Command-W，进程消失且未显示确认框；重新打开后该设置仍被选中。
- 实机选择弹窗询问后 Command-W，确认框正常出现，取消返回窗口。验收后恢复默认“弹窗询问”。
- `git diff --check` 通过。提交：`feat: 新增关闭窗口退出与后台行为设置`。
