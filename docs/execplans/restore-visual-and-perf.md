# ExecPlan：恢复原视觉 + 微调 + 性能五项

## 摘要

用户认为 1.9.0 的原生化改版不如原来好看。本次回滚该改版（`git revert 1ebc4cd`），在原设计上只做对齐级微调，并落地已确认的五项性能优化。业务逻辑不变。

## 范围

- 回滚：侧栏、章节网格、队列、历史、设置全部回到 1.8.5 外观。
- 视觉微调（保持原风格）：
  - 设置页：标签列 104→112pt 且单行；所有分段控件改 `fixedSize()` 左对齐（原来在固定宽度里居中，导致「关闭窗口时」「下载性能」控件错位）；站点按钮从拉伸网格改为左侧紧排（放不下时回退网格）。
  - 侧栏：空闲且队列为空时隐藏底部托盘状态按钮（它只是重复「队列」图标）。
  - 历史：刚保存的记录不再显示「0 秒钟后」。
- 性能：
  1. `DownloadCoordinator` 缓存 `countsSummary()` / `progressSummary()`，仅在 `taskItems` 或页数字典变化时失效；侧栏每次渲染只取一次计数。
  2. 章节位置：去掉 `ChapterFrameKey` 偏好合并，改为每格 `ChapterFrameReporter` 直接写入非发布的 `ChapterFrameStore`，消失时移除。
  3. 拆模型：日志迁到独立的 `ActivityLogStore`（追加日志不再刷新首页）；章节网格抽成 `ChapterGridContent` 并 `.equatable()`，只在分组/选择/折叠变化时重算 160 个格子（输入链接、解析状态变化不再触发）。
  4. Logo 静态缓存；`RelativeDateTimeFormatter` 共享；封面改 `CachedCoverImage`（`NSCache` 解码缓存 + 同 URL 请求合并）。
  5. 日志列表用稳定 `id`；错误过滤在追加时一次判定，维护 `errorEntries` 增量数组。

## 约束

- 架构/状态管理调整，按大幅度修改：版本 `1.9.0` → `1.10.0`。
- 链接输入 `inputURL` 仍留在 `MainViewModel`（被解析、历史回填等逻辑直接使用，拆出会改行为）；其刷新成本已由网格 equatable 隔离消化。

## 验证

- `swift test`：38 项通过（2 项按设计跳过）。
- `LayoutSnapshots` 浅/深色渲染，人工确认外观与 1.8.5 一致，设置页对齐修复生效。
- `scripts/build_app.sh --install` 替换 `/Applications/MangaGlass.app`。
