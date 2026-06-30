# ExecPlan：线条小象图标

## 摘要

将当前白底灰色块面小象改为更简约的线条小象图标。保留白底，只使用单色线条，不做填充块、阴影、渐变、玻璃或多层背景。

本次只改图标资源、版本号和构建产物，不修改业务逻辑与界面结构。

## 用户价值

- 图标从块面灰象变成更轻、更高级的线条风格。
- 应用内 logo 和 AppIcon 风格一致。

## 范围

范围内：

- 替换 `assets/logo.png`、`Sources/MangaGlass/Resources/logo.png`、`assets/AppIcon.iconset/*`、`assets/AppIcon.icns`。
- 将版本从 `1.2.14` 升到 `1.2.15`。
- 构建安装 `/Applications/MangaGlass.app`。
- 提交中文 `feat:` commit。

范围外：

- 不新增依赖。
- 不保留一次性图标生成脚本。
- 不修改主界面布局。

## 约束

- 背景为白色。
- 小象为单色线条，不使用主体填充色块。
- 本次是普通资源补丁，目标版本号 `1.2.15`。

## 修改文件

- `assets/logo.png`
- `Sources/MangaGlass/Resources/logo.png`
- `assets/AppIcon.iconset/*`
- `assets/AppIcon.icns`
- `scripts/build_app.sh`
- `scripts/build_dmg.sh`
- `docs/execplans/line-elephant-logo.md`

## 已确认事实

- 当前工作区开始前没有未提交变更。
- 当前版本号为 `1.2.14`。
- logo 源图为 `1280x1280` PNG。

## 实施计划

### 里程碑 1：生成线条图标

- 用临时 Swift/AppKit 绘图脚本生成白底线条小象。
- 派生 iconset 和 icns。
- 删除临时脚本。

### 里程碑 2：版本、构建与提交

- 更新构建脚本版本到 `1.2.15`。
- 运行 `swift build`。
- 运行 `./scripts/build_app.sh --install`。
- 检查安装版版本号。
- 提交 `feat: 改为线条小象图标`。

## 验证方式

- `swift build` 必须通过。
- `./scripts/build_app.sh --install` 必须通过。
- `/Applications/MangaGlass.app/Contents/Info.plist` 的 `CFBundleShortVersionString` 和 `CFBundleVersion` 必须为 `1.2.15`。
- 图标预览为白底单色线条小象。

## 风险

- 线条图标在 16px 小尺寸可能细节减少；优先保持线条粗细足够可见。

## 决策记录

- 决策：使用本机 AppKit 临时脚本绘制图标。
  原因：不引入新依赖，资源生成后无需保留脚本。

## 进度

- [x] 创建并保存 ExecPlan。
- [x] 生成并替换线条图标资源。
- [x] 更新版本号。
- [x] 完成构建、安装和版本验证。
- [x] 提交 commit。

## 意外发现

- 初次派生 iconset 时 `sips` 循环产生了多余的 `assets/AppIcon.iconset/logo.png`，已删除并显式逐个生成标准 iconset 文件。
- `swift build` 会触碰 `.build` 缓存，提交前已恢复并清理，避免把构建缓存带入 commit。

## 结果与回顾

- 已将 logo 和 AppIcon 改为白底线条小象，应用内资源和安装包资源保持一致。
- 版本已更新为 `1.2.15`。
- `swift build` 和 `./scripts/build_app.sh --install` 均已通过，安装版 `CFBundleShortVersionString` 与 `CFBundleVersion` 均为 `1.2.15`。
