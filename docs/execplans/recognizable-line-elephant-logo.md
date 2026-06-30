# ExecPlan：重画可识别线条小象图标

## 摘要

当前线条图标过于抽象，正面看不像小象。本次只重画 logo/AppIcon，让它保持白底、线条、简洁，但明确具备小象特征：大耳朵、圆头、下垂鼻子、短腿和小尾巴。

不修改主界面布局、下载逻辑或其他业务行为。

## 用户价值

- 图标第一眼更像小象。
- 保留简约干净的白底线条风格。
- 应用内 logo 和 AppIcon 继续保持一致。

## 范围

范围内：

- 替换 `assets/logo.png`、`Sources/MangaGlass/Resources/logo.png`、`assets/AppIcon.iconset/*`、`assets/AppIcon.icns`。
- 将版本从 `1.2.15` 升到 `1.2.16`。
- 构建并安装 `/Applications/MangaGlass.app`。
- 提交中文 `feat:` commit。

范围外：

- 不新增依赖。
- 不修改界面降噪方案。
- 不保留一次性图标生成脚本。

## 约束

- 本次是普通可见资源补丁，目标版本号 `1.2.16`。
- 背景保持白色。
- 小象以线条为主，可使用少量实心眼睛增强识别。
- 图标小尺寸也要能看出耳朵和鼻子。

## 修改文件

- `assets/logo.png`
- `Sources/MangaGlass/Resources/logo.png`
- `assets/AppIcon.iconset/*`
- `assets/AppIcon.icns`
- `scripts/build_app.sh`
- `scripts/build_dmg.sh`
- `docs/execplans/recognizable-line-elephant-logo.md`

## 已确认事实

- 当前工作区开始前干净。
- 当前版本号为 `1.2.15`。
- 上一版线稿由几何圆线组成，用户反馈不像小象。

## 实施计划

### 里程碑 1：重画图标

- 用本机 AppKit 生成更具象的正面小象线稿。
- 同步生成 iconset 和 icns。

### 里程碑 2：版本、构建与提交

- 更新构建脚本版本到 `1.2.16`。
- 运行 `swift build`。
- 运行 `./scripts/build_app.sh --install`。
- 检查安装版版本号。
- 提交 `feat: 重画线条小象图标`。

## 验证方式

- `swift build` 必须通过。
- `./scripts/build_app.sh --install` 必须通过。
- `/Applications/MangaGlass.app/Contents/Info.plist` 的 `CFBundleShortVersionString` 和 `CFBundleVersion` 必须为 `1.2.16`。
- 图标预览为白底、可识别的小象线稿。

## 风险

- 线条图标在 16px 尺寸会丢细节；优先保留头、耳朵、鼻子的轮廓。

## 决策记录

- 决策：继续使用 AppKit 生成 PNG/iconset。
  原因：项目已有这条路径，无需新增设计工具或依赖。

## 进度

- [x] 创建并保存 ExecPlan。
- [x] 完成主要实现。
- [x] 完成验证。
- [x] 提交 commit。

## 意外发现

- AppKit 直接从 `NSImage` 导出时会按 Retina 缩放得到 `2560x2560`，已改为显式 `NSBitmapImageRep` 输出 `1280x1280`。
- 首版线稿坐标翻转，预览后已纠正；后续删掉身体/象牙线条，保留更清楚的头、耳、鼻。
- `swift build` 会产生 `.build` 缓存变更，提交前已清理。

## 结果与回顾

- 已将 logo/AppIcon 改为白底线条小象，图形更强调大耳朵和下垂鼻子。
- `assets/logo.png` 为 `1280x1280`，iconset 和 icns 已重新派生。
- 版本已更新为 `1.2.16`。
- `swift build` 和 `./scripts/build_app.sh --install` 均已通过，安装版 `CFBundleShortVersionString` 与 `CFBundleVersion` 均为 `1.2.16`。
