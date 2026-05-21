# ExecPlan：版本号 1.2.0 与计划版本规则

## 摘要

将 MangaGlass 的应用版本号调整为 `1.2.0`，并把后续版本递增规则写入项目 ExecPlan 模板：普通修改后增加 `0.0.1`，大幅度修改后增加 `0.1.0`。

本次只调整构建产物元数据和项目计划模板，不改变应用运行逻辑、下载逻辑或 UI 行为。

## 用户价值

- 构建出来的 `.app` 和 `.dmg` 会显示新的 `1.2.0` 版本。
- 后续每次实施修改时，有明确的版本递增规则，避免版本号长期停留在旧值。
- 大幅功能变更和普通小改可以用统一规则区分。

## 范围

范围内：

- 更新 `scripts/build_app.sh` 中生成的 `CFBundleShortVersionString` 和 `CFBundleVersion`。
- 更新 `scripts/build_dmg.sh` 中生成的 `CFBundleShortVersionString` 和 `CFBundleVersion`。
- 更新 `.agent/PLANS.md`，加入版本递增规则与 ExecPlan 记录要求。

范围外：

- 不新增自动版本号脚本。
- 不修改 README、发布说明或 Git tag。
- 不改变应用功能代码。

## 约束

- 遵守项目 `AGENTS.md`：复杂任务必须先创建持久 ExecPlan，并随实施更新。
- 版本号采用语义化格式 `major.minor.patch`。
- 本次用户明确指定当前版本为 `1.2.0`。
- 本次属于版本基线设置与模板规则更新，目标版本由用户指定为 `1.2.0`，不再按旧版本自动递增计算。

## 修改文件

- `scripts/build_app.sh`
- `scripts/build_dmg.sh`
- `.agent/PLANS.md`
- `docs/execplans/version-1-2-0-and-plan-rule.md`

## 已确认事实

- 当前 app 版本号在 `scripts/build_app.sh` 和 `scripts/build_dmg.sh` 生成 `Info.plist` 时硬编码为 `0.1.0`。
- 当前 `CFBundleVersion` 硬编码为 `1`。
- 项目已有 `.agent/PLANS.md` 作为 ExecPlan 默认模板。

## 实施计划

### 里程碑 1：保存计划

- 创建本 ExecPlan 文件。
- 可观察结果：`docs/execplans/version-1-2-0-and-plan-rule.md` 存在。

### 里程碑 2：更新构建版本

- 将两个构建脚本生成的 `CFBundleShortVersionString` 改为 `1.2.0`。
- 将两个构建脚本生成的 `CFBundleVersion` 改为 `1.2.0`，保持显示版本和构建版本一致。
- 可观察结果：后续构建产物 `Info.plist` 中版本为 `1.2.0`。

### 里程碑 3：更新计划模板

- 在 `.agent/PLANS.md` 中新增版本递增规则。
- 要求后续 ExecPlan 记录本次修改属于普通修改还是大幅修改，以及目标版本号。
- 可观察结果：后续计划可以直接按模板执行版本递增。

### 里程碑 4：验证

- 运行构建验证。
- 检查生成的 `dist/MangaGlass.app/Contents/Info.plist` 版本字段。

## 验证方式

- `git diff --check`
- `./scripts/build_app.sh`
- `plutil -p dist/MangaGlass.app/Contents/Info.plist | rg "CFBundleShortVersionString|CFBundleVersion"`

## 风险

- `CFBundleVersion` 使用 `1.2.0` 而非单调整数；macOS 允许最多三段整数形式，符合本项目需要。
- 后续是否每次都更新版本依赖实施者遵守 `.agent/PLANS.md`。

## 决策记录

- 决策：本次将 `CFBundleShortVersionString` 和 `CFBundleVersion` 都设置为 `1.2.0`。
  原因：项目当前没有独立 build number 体系，保持两者一致最直观。

## 进度

- [x] 创建并保存 ExecPlan。
- [x] 更新构建版本。
- [x] 更新计划模板。
- [x] 完成验证。

## 意外发现

- `./scripts/build_app.sh` 会重新生成 `dist/MangaGlass.app/Contents/Info.plist`，因此验证后工作区会出现该构建产物变更。

## 结果与回顾

- 已将 `scripts/build_app.sh` 和 `scripts/build_dmg.sh` 的应用版本统一为 `1.2.0`。
- 已在 `.agent/PLANS.md` 中加入版本递增规则：普通修改增加 `0.0.1`，大幅度修改增加 `0.1.0`。
- 已运行 `git diff --check`，无空白错误。
- 已运行 `./scripts/build_app.sh`，构建成功并重新生成 `dist/MangaGlass.app`。
- 已检查 `dist/MangaGlass.app/Contents/Info.plist`，`CFBundleShortVersionString` 与 `CFBundleVersion` 均为 `1.2.0`。
