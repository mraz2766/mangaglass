# ExecPlan：首页状态标记与一键清除

## 摘要与用户价值

移除顶部大号“首页”，用 28 pt 三点状态标记表现待输入、解析中、就绪与错误；链接框增加叉号，一次清除当前搜索和解析内容。

## 设计与范围

- 视觉：沿用系统蓝与中性色，紧凑、无额外卡片。
- 内容：状态标记 → 链接输入与清除 → 原有封面和章节工作区。
- 交互：解析时三点轻微起伏，状态切换使用共享短动效；减少动态效果时静态显示。清除后焦点回到链接框。
- 保留队列、历史、Cookie、目录和日志；不清理下载文件或整个解析缓存。
- 普通行为改动，1.5.0 → 1.5.1，兼容 macOS 13。

## 修改文件

- `Sources/MangaGlass/App/MainViewModel.swift`
- `Sources/MangaGlass/UI/Workspace/DownloadWorkspaceView.swift`
- `Sources/MangaGlass/UI/DesignSystem.swift`
- `Sources/MangaGlass/Services/CopyMangaAPI.swift`（取消后不重试或发送中间结果）
- `Tests/MangaGlassTests/SelectionTests.swift`
- `scripts/build_app.sh`

## 实施计划与风险

1. 保存计划，检查当前解析任务生命周期。
2. 增加可取消任务与请求身份验证，清除后旧结果不能回填。
3. 状态组件、链接清除按钮与焦点反馈。
4. 测试清除边界、构建安装、核对版本并中文提交。

## 进度

- [x] 保存计划。
- [x] 实现与测试。
- [x] 构建安装与提交。

## 结果

- `swift test --scratch-path /tmp/mangaglass-fluid-build --filter SelectionTests`：10 项通过，0 失败。新增验证：清除工作区但保留队列／历史／Cookie／目录、取消尚未开始的解析、旧请求晚到不能覆盖新结果。
- `bash scripts/build_app.sh --install` 成功；已重启安装应用，两个 Bundle 版本均为 1.5.1。
- 实机从“殺戮都市GANTZ”37 卷状态选中章节并搜索“03”，点击链接框叉号后，链接、搜索、封面、章节与选择全部清空，焦点返回链接框；清除按钮与解析按钮进入禁用状态，三点标记恢复待输入。
- 三点标记仅在解析时连续变化，悬停轻微反馈；减少动态效果时不产生位移或连续动画。参考项目的动效规范，继续使用共享 80/160 ms 状态动效。
- `git diff --check` 通过。提交：`feat: 新增首页动态状态标记与一键清除`。
