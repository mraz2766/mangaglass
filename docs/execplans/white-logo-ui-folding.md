# ExecPlan：白底灰象 Logo 与界面折叠降噪

## 摘要

本次继续做低风险 UI 降噪：将 logo/AppIcon 改为白底灰色小象；把工具栏目录路径、分类筛选和底部下载栏做最小折叠，减少页面拥挤感。

不修改解析、下载、队列、缓存、历史、代理等业务逻辑。

## 用户价值

- 图标变成白底灰象，更简约干净。
- 顶部不再用长路径横条占据视觉中心。
- 分类筛选默认收起，章节列表更像主工作区。
- 底部状态栏减少文字按钮挤压。

## 范围

范围内：

- 替换 `assets/logo.png`、`Sources/MangaGlass/Resources/logo.png`、`assets/AppIcon.iconset/*`、`assets/AppIcon.icns`。
- 修改主界面工具栏、分类筛选区和底部下载摘要。
- 将版本从 `1.2.13` 升到 `1.2.14`。
- 构建安装 `/Applications/MangaGlass.app`。
- 提交中文 `feat:` commit。

范围外：

- 不新增设置项。
- 不重写主界面信息架构。
- 不改下载管理页业务逻辑。
- 不新增依赖或保留图标生成脚本。

## 约束

- 本任务涉及多个文件，必须先保存 ExecPlan 再实施。
- 本次属于普通可见 UI/资源补丁，目标版本号 `1.2.14`。
- Logo 背景必须是白色，主体为灰色小象，不使用蓝色背景、白卡片、光晕或玻璃效果。

## 修改文件

- `Sources/MangaGlass/UI/ContentView.swift`
- `assets/logo.png`
- `Sources/MangaGlass/Resources/logo.png`
- `assets/AppIcon.iconset/*`
- `assets/AppIcon.icns`
- `scripts/build_app.sh`
- `scripts/build_dmg.sh`
- `docs/execplans/white-logo-ui-folding.md`

## 已确认事实

- 当前版本号为 `1.2.13`。
- 当前 toolbar 目录路径在 `directoryStatusBar` 中完整展示。
- 分类筛选区由 `volumeSelectionStrip` 常驻展示。
- 底部下载栏按钮文案在窄宽度下容易被挤压。

## 实施计划

### 里程碑 1：重做白底灰象图标

- 用临时 Swift/AppKit 脚本生成白底灰象 PNG。
- 派生 iconset 和 icns。
- 不保留生成脚本。

### 里程碑 2：折叠高噪音 UI

- 目录路径只显示末级目录，完整路径放到 help。
- 分类筛选默认收起，用一个轻量按钮展开/收起。
- 底部下载栏操作按钮改成图标优先，减少文案挤压。

### 里程碑 3：版本、构建与提交

- 更新构建脚本版本到 `1.2.14`。
- 运行 `swift build`。
- 运行 `./scripts/build_app.sh --install`。
- 检查安装版 `Info.plist`。
- 提交 `feat: 简化图标并折叠界面噪音`。

## 验证方式

- `swift build` 必须通过。
- `./scripts/build_app.sh --install` 必须通过。
- `/Applications/MangaGlass.app/Contents/Info.plist` 的 `CFBundleShortVersionString` 和 `CFBundleVersion` 必须为 `1.2.14`。
- 图标预览为白底灰色小象。
- 主界面可展开分类筛选，章节选择、全选、清空、加入队列仍可用。

## 风险

- 分类默认收起可能让首次使用者多一次点击；保留明确的“分类”展开按钮。
- 图标是扁平简化图形，不追求拟物细节。

## 决策记录

- 决策：只折叠目录路径、分类筛选、底部按钮文案。
  原因：这是当前截图里最高噪音的三处，改动最小。

## 进度

- [x] 创建并保存 ExecPlan。
- [x] 重做白底灰象图标。
- [x] 完成界面折叠降噪。
- [x] 更新版本号。
- [x] 完成构建、安装和版本验证。
- [x] 提交 commit。

## 意外发现

- `directoryStatusBar` 从纯表达式改为带局部变量后，Swift opaque return type 需要显式 `return`；已修复。
- `swift build` 会修改仓库中已跟踪的 `.build/` 调试产物，并产生新的未跟踪缓存；这些是验证副作用，已恢复和清理。

## 结果与回顾

- 已将 logo 和 AppIcon 改为白底灰色小象。
- 已将工具栏目录路径折叠为末级目录名，完整路径保留在 hover help。
- 已将分类筛选默认收起，通过“分类”按钮展开，保留全选、清空和分组选择能力。
- 已将底部下载管理、最近下载、日志操作改为图标按钮，减少文字挤压。
- 已将版本更新为 `1.2.14`。
- 验证结果：`swift build` 通过。
- 验证结果：`./scripts/build_app.sh --install` 通过，并已安装到 `/Applications/MangaGlass.app`。
- 验证结果：安装版和 `dist/MangaGlass.app` 的 `CFBundleShortVersionString`、`CFBundleVersion` 均为 `1.2.14`。
