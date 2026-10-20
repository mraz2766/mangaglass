<div align="center">

<img src="./assets/logo.png" alt="MangaGlass" width="104">

# MangaGlass

**粘贴链接，挑好章节，整部漫画下载到本地。**

一个原生 macOS 漫画下载工具，基于 SwiftUI 构建。

[English](./README.md) · 简体中文

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple) ![Swift 6.2](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white) ![Version](https://img.shields.io/badge/version-1.12.1-2C78F2)

<img src="./assets/screenshots/home-ink.png" alt="解析后的章节选择界面" width="900">

</div>

## 亮点

- **一步到位**：粘贴漫画链接回车，封面、分类和全部章节随即列出。
- **选得快**：点选、⇧ 连选、⌘ 加选，或直接在网格上拖出一个框；分类标签一键切换。
- **下得稳**：并发、错峰和自动降速都有限制；每话先写入临时目录，校验完整后才落盘。
- **看得清**：总进度、速度和剩余时间一目了然，任务按漫画分组，失败原因随时可查。
- **随时接上**：书架记住看过的漫画；未完成的队列重启后会提示继续。
- **三套主题**：经典（白蓝玻璃）、墨与纸、石墨，各自带浅色与深色。

## 支持站点

| 站点 | 域名 | 备注 |
| --- | --- | --- |
| 拷贝漫画 | `mangacopy.com` · `2026copy.com` · `copy4000.com` | 分别为主站、备用站、国内站；解析失败时可一键切换镜像 |
| 漫画柜 | `manhuagui.com` | 请求较严格，触发风控时会暂停并提示打开网页验证 |
| 包子漫画 | `baozimh.com` | |

> 解析依赖各站点当前的页面结构。站点改版、限流或屏蔽都可能导致暂时不可用。

## 截图

<table>
  <tr>
    <td width="50%"><img src="./assets/screenshots/start-ink-dark.png" alt="首页：输入链接与继续上次"></td>
    <td width="50%"><img src="./assets/screenshots/download-graphite-dark.png" alt="下载页：总进度与分组任务"></td>
  </tr>
  <tr>
    <td align="center">首页 · 墨与纸 · 深色</td>
    <td align="center">下载 · 石墨 · 深色</td>
  </tr>
</table>

<table>
  <tr>
    <td width="33%"><img src="./assets/screenshots/theme-classic.png" alt="经典主题"></td>
    <td width="33%"><img src="./assets/screenshots/theme-ink.png" alt="墨与纸主题"></td>
    <td width="33%"><img src="./assets/screenshots/theme-graphite.png" alt="石墨主题"></td>
  </tr>
  <tr>
    <td align="center">经典</td>
    <td align="center">墨与纸</td>
    <td align="center">石墨</td>
  </tr>
</table>

## 安装

需要 macOS 13 及以上，以及 Xcode 命令行工具（Swift 6.2）。

```bash
xcode-select --install          # 若尚未安装命令行工具
git clone https://github.com/mraz2766/mangaglass.git
cd mangaglass
scripts/build_app.sh --install --open
```

脚本会编译 Release 版本，生成 `dist/MangaGlass.app`，复制到 `/Applications` 并打开。只想构建、不安装时，去掉 `--install --open` 即可。

## 使用

1. **粘贴链接**：在首页输入框粘贴漫画详情页链接，按回车。拷贝漫画也可以只填 `path_word`（链接里 `/comic/` 后面那一段）。

   ```text
   https://www.mangacopy.com/comic/<path_word>
   https://www.manhuagui.com/comic/<id>/
   https://www.baozimh.com/comic/<slug>
   ```

2. **挑选章节**：
   - 点击选择单话，⇧ 点击选择连续范围，⌘ 点击追加。
   - 在网格空白处拖动，可框选多话。
   - 卷标题右侧的方框可整卷全选或取消。
   - 用上方分类标签只看某一类；搜索和排序在同一行。被隐藏的已选章节仍会一起下载。

3. **加入队列**：底部浮条显示已选数量，点「加入队列」。若目标目录已有同名章节，会询问「保留并补全」还是「覆盖重新下载」。

4. **查看进度**：在侧栏「下载」页开始、暂停或重试失败项。全部结束后会发送系统通知。

下载结果按以下结构保存：

```text
下载目录/
└── 漫画名/
    └── 单行本/                      # 仅当所选章节跨多个分组时才有这一层
        └── 第 1 卷/
            ├── 漫画名-单行本-第 1 卷-0001.jpg
            └── ...
```

正在下载的章节位于 `.下载中-章节名`，完整性检查通过后才会改名为正式目录。

## 设置

| 项目 | 说明 |
| --- | --- |
| 主题 / 外观 | 选择主题，再选跟随系统、浅色或深色 |
| 关闭窗口时 | 询问、直接退出，或留在后台继续下载 |
| 下载目录 | 选择保存位置；也可在首页标题区直接修改 |
| Cookie | 仅在需要登录或访问受限章节时填写，留空则不发送 |
| Copy 图片并发 / 质量 | 并发 4–8，默认 4；默认使用 `c1500x` 高清图，失败时回退标准图 |
| 本地数据 | 清除当前输入、解析结果与缓存，不会删除已下载的文件 |

网络请求遵循 macOS 系统代理设置。

## 常见问题

<details>
<summary><b>解析不到章节</b></summary>

先在浏览器打开同一链接确认页面正常；拷贝漫画可按提示切换镜像。仍然失败时，在设置中清除本地数据后重试，或打开右上角活动日志查看具体原因。
</details>

<details>
<summary><b>浏览器能看，应用里报 403 或内容为空</b></summary>

通常是站点需要登录或校验 Cookie。在浏览器开发者工具中复制该站点的 Cookie，粘贴到设置页后重试。
</details>

<details>
<summary><b>下载中途暂停并提示风控</b></summary>

这是保护机制：漫画柜会提示打开网页完成验证，拷贝漫画会自动冷却一段时间。按提示操作后点「继续」即可，已完成的章节不会重复下载。
</details>

<details>
<summary><b>Dock 里还是旧图标</b></summary>

macOS 会缓存应用图标，退出应用后重新打开即可刷新。
</details>

## 开发

```bash
swift build                     # 调试构建
swift run MangaGlass            # 本地运行
swift test                      # 单元测试
scripts/build_app.sh --install  # Release 构建并安装
scripts/build_dmg.sh            # 生成 dist/MangaGlass.dmg
```

UI 快照：设置 `MANGAGLASS_SNAPSHOT_DIR` 后运行 `swift test --filter LayoutSnapshots`，会把三套主题在浅色和深色下的各页面渲染为 PNG；README 截图用 `MANGAGLASS_README_DIR` 加 `--filter testRenderReadmeShowcase` 生成。

```text
Sources/MangaGlass/
├── App/        入口、窗口行为、主状态（MainViewModel）、日志
├── Models/     站点、漫画、下载任务等数据模型
├── Services/   站点解析（CopyMangaAPI）、下载调度（DownloadCoordinator）、完整性校验、队列持久化
├── UI/         SwiftUI 界面、主题配色、动效
└── Utils/      网络会话与 JSON 工具
scripts/
├── build_app.sh   构建并可选安装 .app
├── build_dmg.sh   打包 .dmg
└── draw_logo.swift  Logo 矢量源，可重新生成全部图标尺寸
```

版本号只在根目录的 `VERSION` 文件里维护，两个构建脚本都从它读取；`build_dmg.sh` 每次都会先完整构建再打包。

较复杂的改动先在 `docs/execplans/` 写执行计划，模板见 `.agent/PLANS.md`。

## 声明

本项目仅供个人学习与研究。请只下载你有权访问的内容，并遵守目标站点的使用条款与版权要求。
