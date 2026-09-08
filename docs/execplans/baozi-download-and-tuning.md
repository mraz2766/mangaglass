# ExecPlan：包子漫画支持、Copy 调速与原子章节交付

## 摘要

新增包子漫画目录和章节图片解析，并把 Copy 章节并发调整为 3、全局图片并发开放为 4–8 可配置。保留现有 80–180ms 错峰与动态惩罚，增加默认开启的 `c1500x` 高清策略、章节临时目录完成后原子发布，以及支持撤销的搜索输入。

## 用户价值

- 可直接粘贴 `baozimh.com` 漫画链接，查看封面、选择章节并下载。
- Copy 下载速度可在保守和更快之间调整，章节和图片并发仍受统一限速保护。
- 中断或失败时只留下明确的 `.下载中-章节名` 暂存目录，完整章节才出现在正式目录。
- 章节搜索误删内容后可用 Command-Z 或 Control-Z 撤销。

## 范围

范围内：

- 新增 Baozi 站点配置、URL 识别、HTML 目录解析、跳转页跟随和图片提取。
- Copy 章节并发固定为 3；图片全局并发设置为 4–8，默认 4。
- Copy 图片质量增加“高清 `c1500x` / 标准”设置，默认高清；高清不可用时保留标准地址回退。
- 继续使用 80–180ms 图片请求错峰和动态惩罚。
- 章节下载写入同级 `.下载中-章节名`，完整 manifest 写入后再原子移动到正式目录。
- 搜索框保留原生文本编辑撤销，并补充 Control-Z 撤销入口。
- 更新中英文 README、站点入口、测试、版本和安装包。

范围外：

- 不提供绕过验证码、登录墙或站点访问控制的逻辑。
- 不改变已有下载文件命名和队列持久化主格式。
- 不将 Baozi 与 Copy 共用镜像回退。

## 约束

- 本次涉及新站点、网络并发、设置持久化和目录提交协议，属于大幅修改，版本 `1.7.0` → `1.8.0`。
- SwiftUI，兼容 macOS 13，不引入第三方 HTML 框架。
- 旧队列缺少质量字段时按默认高清恢复；旧正式目录可复制到暂存目录继续校验和补全。
- 完成后构建并替换 `/Applications/MangaGlass.app`，两个 Bundle 版本均为 `1.8.0`，以中文 `feat:` 提交。

## 修改文件

- `Sources/MangaGlass/Models/MangaModels.swift`
- `Sources/MangaGlass/Services/CopyMangaAPI.swift`
- `Sources/MangaGlass/Services/DownloadCoordinator.swift`
- `Sources/MangaGlass/Services/DownloadOutputLayout.swift`
- `Sources/MangaGlass/Services/DownloadQueueStore.swift`
- `Sources/MangaGlass/App/MainViewModel.swift`
- `Sources/MangaGlass/UI/DesignSystem.swift`
- `Sources/MangaGlass/UI/Workspace/DownloadWorkspaceView.swift`
- `Sources/MangaGlass/UI/Workspace/HistoryAndSettingsWorkspace.swift`
- `Tests/MangaGlassTests/`
- `README.md`
- `README.zh-CN.md`
- `scripts/build_app.sh`
- `docs/execplans/baozi-download-and-tuning.md`

## 已确认事实

- Baozi 漫画页以 `/comic/<slug>` 提供元数据；章节入口使用 `/user/page_direct?comic_id=<slug>&section_slot=<n>&chapter_slot=<n>`。
- 章节入口当前跳转到 `twmanga.com/comic/chapter/...`，页面中的 `amp-img.comic-contain__item` 同时包含 `src` 和 `data-src` 图片地址。
- Copy 高清地址规则为将图片 URL 中 `.c800x.` 替换为 `.c1500x.`；并非所有旧图链都包含该标记。
- 现有 Copy 章节并发为 2，统一图片预算上限为 4，错峰为 80–180ms 并带动态惩罚。
- 当前章节直接写正式目录；manifest 虽能判断完整性，但失败期间正式目录仍可能是半成品。
- SwiftUI 搜索框使用绑定文本，原生 Command-Z 行为可能因状态重建不稳定，且没有 Control-Z 快捷入口。

## 实施计划

### 里程碑 1：Baozi 解析器

- 加入站点配置和适配器，解析漫画元数据、章节列表和章节页图片。
- 对 HTML 实体、重复章节、相对链接和跳转后的图片页做稳定处理。

### 里程碑 2：Copy 并发与高清设置

- 将 Copy 章节并发改为 3。
- 增加 4–8 全局图片并发和高清开关，持久化设置并传入队列任务。
- 高清地址优先，标准地址作为失败回退，继续经过统一请求预算。

### 里程碑 3：暂存目录和搜索撤销

- 增加暂存目录计算、旧正式目录复用、完整 manifest 校验和同卷目录发布。
- 搜索框使用稳定的本地编辑历史，同时支持 Command-Z 与 Control-Z。

### 里程碑 4：验证与交付

- 增加 Baozi HTML、高清地址、并发边界、暂存发布及旧快照兼容测试。
- 运行完整测试和布局快照，构建安装 1.8.0，核对版本并提交。

## 验证方式

- 用保存的 Baozi 页面片段验证漫画名称、封面、章节顺序、跳转地址和图片去重。
- 验证图片并发设置被限制在 4–8，默认 4；Copy 启动章节并发为 3。
- 验证 `.c800x.` 高清转换、无标记地址保持不变及标准回退。
- 验证失败保留暂存目录、成功后正式目录完整且暂存目录消失。
- 验证搜索输入清除后可撤销，切换漫画仍按现有规则清空搜索。
- 运行 `swift test --scratch-path /tmp/mangaglass-1.8.0-tests`、布局快照和 `bash scripts/build_app.sh --install`。

## 风险

- Baozi HTML 由 SSR 框架输出且可能调整 class；解析同时使用语义 meta、章节 query 参数和图片 class，避免依赖随机生成属性。
- 高清 CDN 可能对部分章节返回 404；必须回退原始标准 URL，不能因此让整章失败。
- 目录移动需保持同一卷目录内执行，避免跨卷复制失去原子性。

## 决策记录

- 决策：Baozi 章节 UUID 保存为可重建的跳转路径。
  原因：保持现有模型和队列格式，同时让重试能直接重新解析章节页。
- 决策：Copy 高清为任务级快照，旧任务缺失字段时采用高清。
  原因：设置修改不应悄悄改变已经排队任务的下载质量。
- 决策：高清请求失败时尝试原始标准 URL。
  原因：优先满足默认高清，同时保证旧图链和不支持 `c1500x` 的章节可下载。
- 决策：正式章节目录在暂存下载期间继续保留；“保留已有”复制可复用文件到暂存目录，“覆盖”从空暂存目录开始。
  原因：下载失败或应用异常退出时不能提前删除已发布的完整章节，只有新 manifest 完整后才替换正式目录。

## 进度

- [x] 创建并保存 ExecPlan。
- [x] 完成 Baozi 解析、图片域名容错、Copy 并发与质量设置。
- [x] 完成暂存目录发布、搜索撤销、持久化兼容和文档更新。
- [x] 完成自动测试、实时站点测试、布局矩阵、构建和安装。
- [x] 提交中文 `feat:` commit。

## 意外发现

- Baozi 章节页当前返回 `s1.bzcdn.net` 图片地址，本机实测该域名 TLS 握手失败；相同路径在 `static-tw.baozimh.com` 与 `s1.baozimh.com` 返回 200。下载器保留页面地址优先，并在连接、证书、DNS 或超时错误时依次切换到这两个站点图片域名，不关闭证书校验。

## 结果与回顾

- MangaGlass 已新增包子漫画站点入口、漫画目录解析、章节跳转解析和阅读图片提取；当前 Baozi 实时样例成功解析超过 500 个章节并取得章节图片列表。
- Copy 章节并发固定为 3；全局图片并发可配置 4–8，默认 4。高清模式默认将 `c800x` 候选提升到 `c1500x`，404 时回退标准图链。原有 80–180ms 错峰、动态惩罚和恢复探测保留。
- 下载先写同级 `.下载中-章节名`。失败时保留暂存结果，原正式章节保持可用；只有完整 manifest 校验通过后才发布新目录。
- 章节搜索支持空格分词、大小写／变音符／全半角折叠，并为章节搜索及首页链接输入提供 Control-Z 撤销；系统 Command-Z 继续由原生文本框处理。
- 完整测试执行 37 项，2 项按环境跳过，0 失败；启用网络的 Baozi 实时解析测试单独通过。布局验收矩阵生成 27 张截图并通过。
- `bash scripts/build_app.sh --install` 成功；`dist/MangaGlass.app` 与 `/Applications/MangaGlass.app` 的 `CFBundleShortVersionString`、`CFBundleVersion` 均为 `1.8.0`。
- 本轮以中文 `feat:` 提交，计划、源码、测试、文档和 1.8.0 构建产物保持一致。
