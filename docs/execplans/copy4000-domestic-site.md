# ExecPlan：新增拷贝漫画国内站

## 摘要与用户价值

将 `https://www.copy4000.com/` 以“国内站”加入站点入口、链接识别和镜像回退，方便用户使用该入口解析漫画。

## 范围与约束

- 沿用拷贝漫画现有解析、下载和镜像策略，不调整默认站点及持久化格式。
- 普通修改，版本 `1.4.1` → `1.4.2`；构建安装至 `/Applications/MangaGlass.app` 并提交中文 `feat:`。

## 已确认事实

- 两处 UI 入口由 `CopyMangaMirror.allCases` 生成；解析回退使用同一枚举。
- 站点首页可读取，并自行标注为大陆访问地址；不据此保证所有网络下均可访问。

## 修改文件

- `Sources/MangaGlass/Models/MangaModels.swift`
- `Sources/MangaGlass/App/MainViewModel.swift`
- `Sources/MangaGlass/Services/DownloadCoordinator.swift`
- `Sources/MangaGlass/Services/CopyMangaAPI.swift`
- `README.md`、`README.zh-CN.md`、`scripts/build_app.sh`

## 实施计划

1. 添加国内站枚举和展示名称，同步拷贝漫画域名判断及图片域名提示。
2. 更新支持列表与版本，验证域名识别和回退候选。
3. 构建安装，核对版本，提交并记录结果。

## 验证方式

- 编译模型执行域名、名称与回退断言。
- `bash scripts/build_app.sh --install`，核对安装版本和 `git diff --check`。

## 风险与决策

- 网络可用性取决于站点与本机环境；国内站沿用已有镜像 API 候选与网页解析回退。
- 顺序为主站、备用站、国内站，输入国内站链接时仍优先该站。

## 进度

- [x] 保存计划。
- [x] 实现及验证。

## 结果与回顾

- 国内站已经加入共享镜像枚举，下载页和设置页自动显示“国内站”。
- 下载并发类型判断复用镜像枚举，图片域名提示同步支持新域名。
- 编译模型并运行断言通过：展示名称、大小写及 www 域名识别、国内站优先回退、API 候选和停用站点排除。
- Release 构建安装通过；安装应用两个 Bundle 版本均为 `1.4.2`；`git diff --check` 通过。
- 已读取站点首页；未执行完整章节解析与下载，不保证具体网络环境下的端到端可用性。
