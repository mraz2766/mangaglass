# ExecPlan：菜单闪烁与单背景图标修正

## 摘要

本次修复两个用户可见问题：下载时打开主界面“更多”的二级菜单会闪烁，以及 logo/AppIcon 仍存在蓝白双背景叠层。实现遵循最小改动：菜单触发器回到原生菜单样式，图标资源改为单一纯色背景加扁平小象。

不修改解析、下载、队列、缓存、历史、代理等业务逻辑。

## 用户价值

- 下载过程中打开“更多 -> 外观”等二级菜单时不再因为自定义 hover 动画反复闪烁。
- logo 和 AppIcon 层级更少，只有一个背景色和小象主体。
- 应用版本和构建产物同步更新，安装版可直接使用。

## 范围

范围内：

- 修改主界面 `更多` 菜单触发器样式。
- 替换 `assets/logo.png`、`Sources/MangaGlass/Resources/logo.png`、`assets/AppIcon.iconset/*`、`assets/AppIcon.icns`。
- 将版本从 `1.2.12` 升到 `1.2.13`。
- 构建并安装 `/Applications/MangaGlass.app`。
- 提交中文 `feat:` commit。

范围外：

- 不重写菜单结构。
- 不新增依赖或长期保留图标生成脚本。
- 不改下载管理页已使用原生菜单的 `更多`。
- 不继续扩大页面信息架构调整。

## 约束

- 按项目规则，本任务先保存 ExecPlan 再实施。
- 本次属于普通可见 UI/资源补丁，目标版本号 `1.2.13`。
- 背景必须只有一层：禁止白色内卡片、蓝色外圈、渐变光晕、阴影和玻璃高光。
- 小象主体可以使用少量同色系蓝灰区分部件，但这些不属于背景层。

## 修改文件

- `Sources/MangaGlass/UI/ContentView.swift`
- `assets/logo.png`
- `Sources/MangaGlass/Resources/logo.png`
- `assets/AppIcon.iconset/*`
- `assets/AppIcon.icns`
- `scripts/build_app.sh`
- `scripts/build_dmg.sh`
- `docs/execplans/menu-logo-noise-reduction.md`

## 已确认事实

- 当前工作区开始前没有未提交变更。
- 主界面 `toolbarSecondaryMenu` 的 `Menu` 触发器使用 `MGActionButtonStyle(variant: .ghost)`。
- 下载管理页 `更多` 已使用 `.menuStyle(.borderlessButton)`。
- 当前版本号为 `1.2.12`。
- logo 资源为 `1280x1280` PNG，AppIcon 由 `assets/AppIcon.iconset` 和 `assets/AppIcon.icns` 提供。

## 实施计划

### 里程碑 1：修复菜单闪烁

- 将主界面 `更多` 菜单触发器改为原生 borderless menu 样式。
- 不新增状态变量或防抖逻辑。

### 里程碑 2：重做单背景图标

- 用本机 Swift/AppKit 临时绘图生成单背景扁平小象源图。
- 替换 logo PNG、iconset PNG，并用 `iconutil` 生成 `AppIcon.icns`。
- 人眼检查新图标没有白色内卡片或蓝白双背景叠层。

### 里程碑 3：版本、构建与提交

- 更新构建脚本版本到 `1.2.13`。
- 运行 `swift build`。
- 运行 `./scripts/build_app.sh --install`。
- 检查安装版 `Info.plist`。
- 提交 `feat: 修复菜单闪烁并简化图标视觉`。

## 验证方式

- `swift build` 必须通过。
- `./scripts/build_app.sh --install` 必须通过。
- `/Applications/MangaGlass.app/Contents/Info.plist` 的 `CFBundleShortVersionString` 和 `CFBundleVersion` 必须为 `1.2.13`。
- 图标预览必须只有单一背景色加小象主体。
- 下载时打开 `更多 -> 外观 -> 主题模式/皮肤` 不应持续闪烁。

## 风险

- 原生菜单样式可能与自定义按钮视觉略有差异，但换来稳定菜单交互。
- AppKit 绘图生成的扁平小象是简化图形，不追求复杂拟物细节。

## 决策记录

- 决策：菜单闪烁通过删除主界面 `更多` 的自定义按钮样式解决。
  原因：这是最小根因修复，避免给菜单新增状态机。

- 决策：图标生成脚本不落库。
  原因：这是一次性资源生成，长期保留脚本会增加维护面。

## 进度

- [x] 创建并保存 ExecPlan。
- [x] 修复菜单触发器样式。
- [x] 重做 logo 和 AppIcon。
- [x] 更新版本号。
- [x] 完成构建、安装和版本验证。
- [x] 提交 commit。

## 意外发现

- 临时 AppKit 绘图第一次按 Retina backing 生成了 `2560x2560` PNG；已用 `sips` 压回计划要求的 `1280x1280`，再重新派生 iconset 和 icns。
- `swift build` 会修改仓库中已跟踪的 `.build/` 调试产物，并产生新的未跟踪缓存；这些是验证副作用，已恢复和清理。

## 结果与回顾

- 已将主界面 `更多` 菜单触发器改为原生 `.menuStyle(.borderlessButton)`，去掉自定义 hover 动画。
- 已删除 toolbar logo 外层白底、描边和阴影，避免 UI 中再次出现蓝白双背景叠层。
- 已替换 logo、AppIcon.iconset 和 AppIcon.icns；新图标为单一浅蓝背景加扁平小象主体。
- 已将版本更新为 `1.2.13`。
- 验证结果：`swift build` 通过。
- 验证结果：`./scripts/build_app.sh --install` 通过，并已安装到 `/Applications/MangaGlass.app`。
- 验证结果：安装版 `CFBundleShortVersionString` 和 `CFBundleVersion` 均为 `1.2.13`。
