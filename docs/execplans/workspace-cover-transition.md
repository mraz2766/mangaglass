# ExecPlan：优化工作区切换与漫画封面入场

## 摘要

修复左侧导航切换时下载工作区及漫画封面看起来停在固定位置后突然出现的问题。当前通过 `.id(destination)` 强制重建单个工作区，未形成可动画的旧新视图交接；缓存命中的 `AsyncImage` 成功状态也没有入场过渡。

本次为小型交互优化，版本从 `1.3.2` 升至 `1.3.3`。

## 用户价值

- 切换下载、队列、历史和设置时，旧页面淡出、新页面轻微上移淡入，空间关系连续且不抢眼。
- 回到下载页时，已缓存的漫画封面也会自然淡入，不再像固定位置突然冒出。
- 开启“减少动态效果”时，保留状态切换但关闭非必要的位移和缩放动画。

## 修改文件

- `Sources/MangaGlass/UI/ContentView.swift`
- `Sources/MangaGlass/UI/Workspace/DownloadWorkspaceView.swift`
- `scripts/build_app.sh`
- `scripts/build_dmg.sh`
- `docs/execplans/workspace-cover-transition.md`

## 实施计划

### 里程碑 1：建立真实页面交接

- 在同一个 `ZStack` 中按导航 destination 条件渲染工作区，使 SwiftUI 能同时处理旧页面移除和新页面插入。
- 移除强制 `.id(destination)` 重建，采用 180ms 的低幅度淡入/淡出与纵向位移。
- 尊重 `accessibilityReduceMotion`。

### 里程碑 2：封面加载入场

- 为 `AsyncImage.success` 封面添加一次 180ms 的透明度与极小缩放入场。
- 漫画 URL 变化时复位动画状态；加载中和失败时继续使用原有占位内容。

### 里程碑 3：验证与交付

- 更新构建版本到 `1.3.3`，构建并安装应用。
- 验证导航切换和已缓存封面回到下载页时均有连续过渡。
- 提交中文 `feat:` 版本提交并记录结果。

## 验证方式

- `swift build` 和 `./scripts/build_app.sh --install` 通过。
- 在有已解析漫画与缓存封面的状态下切换“下载 → 队列 → 下载”，确认页面与封面不再突然出现。
- `/Applications/MangaGlass.app` 的版本为 `1.3.3`。

## 决策记录

- 决策：使用 SwiftUI 条件视图的插入/移除 transition，而不是手工叠加旧视图的定时器。
  原因：生命周期更可靠，不会因快速连续切换留下陈旧页面。

- 决策：动效限定为 180ms、8pt 位移和 0.98 → 1.0 缩放。
  原因：为工作台提供连续性，不引入装饰性或拖慢操作的动效。

## 进度

- [x] 创建并保存 ExecPlan。
- [x] 完成页面与封面过渡。
- [x] 更新版本、构建并安装应用。
- [x] 提交并完成回顾。

## 意外发现

- 当前 `.transition` 绑定在被 `.id(destination)` 重建的单一工作区上，不能稳定形成旧新页面交接。
- 替换时遗留了重复的 `@ViewBuilder` 标注，已在首次编译中发现并移除；后续构建通过。

## 结果与回顾

- 已将单一 `.id(destination)` 工作区替换为同级条件工作区；导航改变时旧页移除、新页插入均使用 180ms 的透明度和小幅纵向 transition。
- 已新增 `AnimatedCoverImage`：封面成功加载或从缓存恢复时，以 180ms 的 0.98 → 1.0 缩放与淡入进入；减少动态效果时直接呈现。
- 验证结果：`swift build`、`./scripts/build_app.sh --install` 成功，`/Applications/MangaGlass.app` 版本为 `1.3.3`。真实应用状态读取确认已缓存的漫画封面与章节工作区稳定渲染；窗口检测到外部交互后未继续注入点击，以免打断用户操作。
- 已完成版本提交。
