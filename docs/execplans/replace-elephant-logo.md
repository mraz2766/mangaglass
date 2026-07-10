# ExecPlan：替换 MangaGlass 手绘小象图标

## 摘要

将用户确认的手绘小象插画接入 MangaGlass，作为应用内品牌 Logo 和 macOS 应用图标。图标使用米白纸张背景、低饱和蓝灰和保留留白的小象主体，替代现有资源中的小象图标。

本次是可见品牌资源更新，版本从 `1.3.0` 升至 `1.3.1`。

## 用户价值

- 侧栏和应用包使用同一枚高辨识度、温暖而克制的小象品牌形象。
- Dock、Finder 与应用内的图标在所有 macOS 标准尺寸中保持一致的构图和清晰度。

## 范围

范围内：

- 使用 `/Users/mraz/.codex/generated_images/019f499d-edcd-75e1-8eba-18b892ea4fe6/exec-9f53d1a4-f7cb-4da9-8945-4365a2ea6663.png` 作为新的图标母版。
- 替换 `assets/logo.png`、`Sources/MangaGlass/Resources/logo.png`、`assets/AppIcon.iconset/` 的全部标准尺寸和 `assets/AppIcon.icns`。
- 将构建脚本版本更新到 `1.3.1`，构建、安装并检查应用包。

范围外：

- 不调整 SwiftUI 布局、业务逻辑、解析和下载行为。
- 不生成新的插画变体，也不修改 README 内容。

## 约束

- 生成图是正方形有底色的 App Icon，不做透明抠图或裁剪；保留原始构图和留白。
- 所有 iconset 文件必须使用 macOS 标准命名和尺寸，并通过 `iconutil` 生成 `.icns`。
- 完成后运行 `swift build`、`./scripts/build_app.sh --install`，将产物替换到 `/Applications/MangaGlass.app`。
- 版本更新后必须使用中文 `feat:` 提交信息创建 Git commit。

## 修改文件

- `assets/logo.png`
- `Sources/MangaGlass/Resources/logo.png`
- `assets/AppIcon.iconset/*`
- `assets/AppIcon.icns`
- `scripts/build_app.sh`
- `scripts/build_dmg.sh`
- `docs/execplans/replace-elephant-logo.md`

## 已确认事实

- 新图标母版为 1254×1254 PNG。
- 项目当前 Logo 资源为 1280×1280 PNG；当前 `.icns` 为 1024×1024。
- `build_app.sh` 和 `build_dmg.sh` 都从 `assets/AppIcon.icns` 复制应用图标。
- SwiftUI 侧栏的 `BrandMarkView` 从 `Bundle.module` 加载 `Resources/logo.png`。

## 实施计划

### 里程碑 1：替换图标资源

- 将生成的小象插画写入两个 PNG Logo 资源。
- 从同一母版生成 16、32、128、256、512 和 1024 像素 iconset 文件，生成新的 `.icns`。

### 里程碑 2：打包与验证

- 将两个构建脚本版本号更新到 `1.3.1`。
- 构建 Swift 包和 Release 应用，安装至 `/Applications/MangaGlass.app`。
- 检查应用包版本、图标文件和应用内资源尺寸。

### 里程碑 3：提交与回顾

- 更新进度、决策、意外发现和结果。
- 提交本次版本更新，使用中文 `feat:` 提交信息。

## 验证方式

- 每个 iconset 文件存在且尺寸符合文件名要求。
- `iconutil --convert icns` 成功，`assets/AppIcon.icns` 为可读的 1024 像素图标。
- `swift build`、`./scripts/build_app.sh --install` 成功。
- `/Applications/MangaGlass.app/Contents/Info.plist` 的 `CFBundleShortVersionString` 为 `1.3.1`，并包含更新后的 `AppIcon.icns` 与 Logo bundle 资源。

## 风险

- 极小尺寸会降低手绘线条辨识度；需从同一高分辨率母版用高质量缩放生成。
- 图标资源变更必须同步到 `assets`、SwiftPM bundle 和应用包，否则 Dock 与应用内 Logo 会不一致。

## 决策记录

- 决策：直接采用用户刚确认的生成插画作为唯一图标母版。
  原因：用户明确要求将该 Logo 替换到应用中，且图像已满足正方形、留白、无文字与低饱和配色约束。

- 决策：保留插画的米白纸张背景，不做透明抠图。
  原因：它符合用户的高级极简和纸张质感要求，且作为 macOS App Icon 的完整方形背景能稳定呈现细小手绘线条。

## 进度

- [x] 创建并保存 ExecPlan。
- [x] 替换 Logo、iconset 和 `.icns` 资源。
- [x] 更新版本并构建安装应用。
- [x] 提交版本更新并完成回顾。

## 意外发现

- 新图标母版是 1254×1254，而非常见的 1024×1024；它仍高于 iconset 最大所需分辨率，使用系统缩放生成 1024px 层级即可保持质量。

## 结果与回顾

- 已将生成的小象插画同步替换到 `assets/logo.png`、SwiftPM `Resources/logo.png`、十个标准 iconset PNG 和 `assets/AppIcon.icns`。
- `iconutil` 成功生成 1024px `.icns`；图标母版与应用内两个 Logo PNG 分别保持 1254×1254。
- 验证结果：`swift build` 与 `./scripts/build_app.sh --install` 已通过；`/Applications/MangaGlass.app` 版本为 `1.3.1`。
- SHA-256 验证：资产 `.icns` 与已安装应用的 `Contents/Resources/AppIcon.icns` 一致；两个项目 Logo PNG 与已安装的 SwiftPM bundle `logo.png` 一致。
- 已完成本次版本更新提交。
