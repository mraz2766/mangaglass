# ExecPlan：修复侧栏整行点击区域

## 摘要

修复 MangaGlass 侧栏导航只能点击文字或图标附近才会切换页面的问题。将每个导航项的完整可见行定义为矩形命中区域，保持现有导航、视觉样式和可访问性名称不变。

本次为小型交互修复，版本从 `1.3.1` 升至 `1.3.2`。

## 用户价值

- 用户可以点击侧栏导航项的任意空白位置切换下载、队列、历史和设置。
- 侧栏在鼠标操作时更符合桌面应用的整行导航预期。

## 修改文件

- `Sources/MangaGlass/UI/Workspace/WorkspaceChrome.swift`
- `scripts/build_app.sh`
- `scripts/build_dmg.sh`
- `docs/execplans/sidebar-row-hit-target.md`

## 实施计划

### 里程碑 1：扩大命中区域

- 在导航按钮的全宽标签上应用 `contentShape(Rectangle())`，使已绘制背景与空白区域都触发同一按钮。
- 不调整导航 destination、图标、文本、计数或辅助功能标签。

### 里程碑 2：验证与交付

- 更新两个构建脚本版本为 `1.3.2`。
- 运行 `swift build`、`./scripts/build_app.sh --install` 并检查安装应用版本。
- 提交中文 `feat:` 版本提交，并记录结果。

## 验证方式

- 编译通过。
- 侧栏每个导航项的全宽行可命中，而不要求鼠标落在文字上。
- `/Applications/MangaGlass.app` 的版本为 `1.3.2`。

## 决策记录

- 决策：在现有 Button 标签上补充全宽矩形命中测试区域，而不改为手势或额外覆盖层。
  原因：保留 SwiftUI Button 的键盘、辅助功能和禁用态语义，改动最小。

## 进度

- [x] 创建并保存 ExecPlan。
- [x] 修复侧栏导航命中区域。
- [x] 更新版本、构建并安装应用。
- [x] 提交并完成回顾。

## 意外发现

- 真实应用验收中，点击“队列”文字右侧的空白区域后成功切换到队列工作区，确认全宽命中区域生效。

## 结果与回顾

- 已在导航标签的全宽布局上添加 `contentShape(Rectangle())`，不影响原有 Button、辅助功能标签或视觉状态。
- 验证结果：`swift build`、`./scripts/build_app.sh --install` 成功，`/Applications/MangaGlass.app` 版本为 `1.3.2`。
- 已完成版本提交。
