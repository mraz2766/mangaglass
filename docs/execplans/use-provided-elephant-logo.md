# ExecPlan：使用用户提供的小象图做 Logo

## 摘要

将当前自绘线条 logo 替换为用户提供的图片内容。处理重点是只保留中间小象和一点暖黄色背景，裁掉截图外部大面积白色底，不额外新增白底或重绘图形。

本次只改图标资源、版本号和构建产物，不修改业务逻辑、界面布局或下载行为。

## 用户价值

- logo 直接使用用户认可的图形方向。
- 去掉外层截图白底后，应用图标不会再出现多层底色。
- AppIcon 和应用内 logo 保持一致。

## 范围

范围内：

- 从用户提供图片裁出中间暖黄色图标区域。
- 替换 `assets/logo.png`、`Sources/MangaGlass/Resources/logo.png`、`assets/AppIcon.iconset/*`、`assets/AppIcon.icns`。
- 将版本从 `1.2.16` 升到 `1.2.17`。
- 构建并安装 `/Applications/MangaGlass.app`。
- 提交中文 `feat:` commit。

范围外：

- 不重绘小象。
- 不新增依赖。
- 不修改主界面降噪或折叠。

## 约束

- 本次是普通可见资源补丁，目标版本号 `1.2.17`。
- 保留中间图标自带的一点暖黄色背景。
- 外围截图白底不进入最终 logo。
- 最终 `assets/logo.png` 输出为 `1280x1280`。

## 修改文件

- `assets/logo.png`
- `Sources/MangaGlass/Resources/logo.png`
- `assets/AppIcon.iconset/*`
- `assets/AppIcon.icns`
- `scripts/build_app.sh`
- `scripts/build_dmg.sh`
- `docs/execplans/use-provided-elephant-logo.md`

## 已确认事实

- 当前工作区开始前干净。
- 当前版本号为 `1.2.16`。
- 用户提供图片为 `1254x1254` PNG。

## 实施计划

### 里程碑 1：裁切并替换图标

- 裁掉源图外部白色截图底，保留中间圆角暖黄色图标和小象。
- 生成 `1280x1280` logo。
- 派生 AppIcon iconset 和 icns。

### 里程碑 2：版本、构建与提交

- 更新构建脚本版本到 `1.2.17`。
- 运行 `swift build`。
- 运行 `./scripts/build_app.sh --install`。
- 检查安装版版本号。
- 提交 `feat: 使用用户提供的小象图标`。

## 验证方式

- `swift build` 必须通过。
- `./scripts/build_app.sh --install` 必须通过。
- `/Applications/MangaGlass.app/Contents/Info.plist` 的 `CFBundleShortVersionString` 和 `CFBundleVersion` 必须为 `1.2.17`。
- 预览最终 logo，确认没有把截图外部白底裁进去。

## 风险

- 源图是截图而非透明素材，裁切边界需要用视觉检查确认。

## 决策记录

- 决策：用本机图像工具裁切源图，不做 AI 重绘。
  原因：用户明确要求用这张图片，最小改动是裁切并派生资源。

## 进度

- [x] 创建并保存 ExecPlan。
- [x] 完成主要实现。
- [x] 完成验证。
- [x] 提交 commit。

## 意外发现

- 本机没有 Pillow，已改用 macOS 自带 `sips` 裁切和缩放，避免新增依赖。
- 初次裁切带入了中间圆角卡片外的一点灰白角，已收紧裁切到暖黄色背景内部。
- `swift build` 会产生 `.build` 缓存变更，提交前已恢复并清理。

## 结果与回顾

- 已使用用户提供图片裁出中间小象和淡黄色背景，没有保留外层截图白底。
- `assets/logo.png` 为 `1280x1280`，AppIcon iconset 和 icns 已重新派生。
- 版本已更新为 `1.2.17`。
- `swift build` 和 `./scripts/build_app.sh --install` 均已通过，安装版 `CFBundleShortVersionString` 与 `CFBundleVersion` 均为 `1.2.17`。
