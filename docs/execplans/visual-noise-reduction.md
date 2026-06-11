# ExecPlan：MangaGlass 视觉降噪

## 摘要

本次目标是做一轮低风险的视觉降噪，不改变解析、下载、队列、历史、缓存、代理等业务行为。重点把界面从“多层玻璃卡片 + 多处胶囊状态 + 多主题强风格”收敛为更安静的桌面工具界面：中性底座、少量 accent、清晰主操作、减少装饰性容器。

本次实现会保留现有信息架构和 `MainViewModel` 对外接口，只调整 SwiftUI 表现层、共享视觉 token、版本号和构建安装产物。

## 用户价值

- 用户打开应用后，URL 输入和“加载”路径更清楚。
- 章节选择区更像工作列表，减少卡片、胶囊和描边造成的扫读负担。
- 下载摘要更接近状态栏，保留关键进度但不压过主工作区。
- 下载管理页保留密度和功能，同时降低行项目和筛选栏的视觉噪音。

## 范围

范围内：

- 收敛 `DesignSystem.swift` 中的背景、面板、描边、阴影、字体和状态 pill。
- 降低 `ContentView.swift` 中 toolbar、左侧信息、章节区和底部下载摘要的装饰强度。
- 降低 `DownloadManagerView.swift` 中筛选栏、任务行和页脚的卡片/胶囊重量。
- 将版本从 `1.2.11` 升到 `1.2.12`。
- 构建 app 并替换 `/Applications/MangaGlass.app`。

范围外：

- 不修改解析、网络、下载、缓存、历史、代理或持久化逻辑。
- 不新增第三方依赖。
- 不新增页面或重写信息架构。
- 不更新 README 截图。

## 约束

- 本任务涉及多个 UI 文件，必须先保存本 ExecPlan 再实现。
- 本次按普通可见 UI 优化处理，目标版本号为 `1.2.12`，同步更新 `scripts/build_app.sh` 和 `scripts/build_dmg.sh`。
- 实现过程中若某个主题降噪后对比度不足，优先保证可读性和 macOS 原生感，并记录决策。
- 每次偏离计划必须先记录到“决策记录”再继续。

## 修改文件

- `Sources/MangaGlass/UI/DesignSystem.swift`
- `Sources/MangaGlass/UI/ContentView.swift`
- `Sources/MangaGlass/UI/DownloadManagerView.swift`
- `scripts/build_app.sh`
- `scripts/build_dmg.sh`
- `docs/execplans/visual-noise-reduction.md`

## 已确认事实

- 主界面位于 `Sources/MangaGlass/UI/ContentView.swift`。
- 共享 UI token 和修饰器位于 `Sources/MangaGlass/UI/DesignSystem.swift`。
- 下载管理页位于 `Sources/MangaGlass/UI/DownloadManagerView.swift`。
- 当前版本号在 `scripts/build_app.sh` 和 `scripts/build_dmg.sh` 中均为 `1.2.11`。
- `scripts/build_app.sh --install` 会构建 `dist/MangaGlass.app` 并替换 `/Applications/MangaGlass.app`。
- 当前工作区在开始前没有未提交变更。

## 实施计划

### 里程碑 1：收敛设计系统

- 将所有主题的字体设计收敛到 `.default`，避免皮肤切换造成明显人格变化。
- 将浅色和深色背景改成更中性的 macOS 工具底色。
- 降低面板填充、描边和阴影强度。
- 降低普通状态 pill 的视觉重量，选中态保留轻 accent。

### 里程碑 2：主界面降噪

- 弱化全局 accent 背景 wash。
- 保留 toolbar 的主操作路径，但降低辅助行和目录状态的强调。
- 左侧统计从嵌套小卡片改为轻量数字行。
- 章节区和选中浮条降低阴影、描边和胶囊密度。
- 底部下载摘要改得更接近状态栏。

### 里程碑 3：下载管理页降噪

- 筛选栏和 header 降低 panel 强度。
- 任务行降低卡片背景和状态色块阴影。
- 页脚保留进度、任务、速度和主要操作，但降低 dashboard 感。

### 里程碑 4：版本、构建与安装

- 将构建脚本版本改为 `1.2.12`。
- 运行 `swift build`。
- 运行 `./scripts/build_app.sh --install`。
- 检查安装后的 `Info.plist` 版本。

## 验证方式

- `swift build` 必须通过。
- `./scripts/build_app.sh --install` 必须通过。
- `/Applications/MangaGlass.app/Contents/Info.plist` 中 `CFBundleShortVersionString` 和 `CFBundleVersion` 必须为 `1.2.12`。
- 通过代码检查确认 UI 改动没有触碰 ViewModel、服务层和下载逻辑。

## 风险

- 过度降低描边和背景可能影响浅色模式下的区域边界。
- SwiftUI 复杂 `ViewBuilder` 中视觉替换可能触发类型推断问题。
- 主题收敛如果过猛，可能让用户原本选择的皮肤差异变小。

## 决策记录

- 决策：本次按普通 UI 优化递增补丁版本到 `1.2.12`。
  原因：改动用户可见但不改变业务行为、状态模型或主要信息架构。

- 决策：优先收敛设计 token，再做局部视图降噪。
  原因：当前视觉噪音主要来自共享面板、描边、阴影和 pill 被大量复用。

## 进度

- [x] 创建并保存 ExecPlan。
- [x] 收敛共享设计系统。
- [x] 完成主界面降噪。
- [x] 完成下载管理页降噪。
- [x] 更新版本号。
- [x] 完成构建、安装和版本验证。

## 意外发现

- 第一次直接运行 `./scripts/build_app.sh --install` 返回空输出异常退出；用 `bash -x ./scripts/build_app.sh --install` 重跑后构建和安装成功，未发现脚本逻辑错误。
- `swift build` 会修改仓库中已跟踪的 `.build/` 调试产物；这些是验证副作用，已恢复 `.build/`，避免把无关构建缓存混入本次改动。

## 结果与回顾

- 已收敛共享设计系统：字体统一为系统默认，背景改为中性浅灰/深灰，面板、描边、阴影和普通状态 pill 都降低视觉重量。
- 已完成主界面降噪：弱化全局 accent wash，降低 toolbar、侧栏、章节面板和底部下载摘要的面板强度，左侧统计从嵌套小卡片改为轻量数字行，章节项改为更轻的可选行视觉。
- 已完成下载管理页降噪：header、筛选栏、列表容器、任务行、页脚和漫画耗时 chip 均降低卡片/胶囊重量，保留状态色和主要操作。
- 已将 `scripts/build_app.sh` 和 `scripts/build_dmg.sh` 版本更新为 `1.2.12`。
- 验证结果：`swift build` 通过。
- 验证结果：`bash -x ./scripts/build_app.sh --install` 通过，并已安装到 `/Applications/MangaGlass.app`。
- 验证结果：`/Applications/MangaGlass.app/Contents/Info.plist` 中 `CFBundleShortVersionString` 和 `CFBundleVersion` 均为 `1.2.12`。
