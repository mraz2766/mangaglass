# MangaGlass

macOS 漫画解析与下载工具，基于 SwiftUI 和 Swift Package Manager 构建。

适用场景：
- 输入漫画页面链接，解析卷 / 章节列表
- 选择章节后批量下载到本地
- 支持代理、Cookie、下载队列和失败重试

当前主要适配站点：
- CopyManga 系列：`mangacopy.com`、`2025copy.com`、`2026copy.com`
- `manhuagui.com`

## 首页展示
<div align="center">
  <img src="./assets/home.png" alt="Home Screenshot" width="800">
</div>

## 项目定位

这是一个本地桌面应用，不是通用爬虫框架，也不是后端服务。

核心职责：
- 解析站点页面或接口，提取漫画、分组、章节、图片地址
- 在 macOS 上提供可操作的下载 UI
- 在速度和风控之间做保守平衡

不负责：
- 云端同步
- 多平台客户端
- 长期稳定的站点兼容承诺

## 技术栈

- Swift 6.2
- SwiftUI
- Swift Package Manager
- macOS 13+

## 快速开始

### 1. 环境要求

- macOS 13 或更高版本
- Xcode Command Line Tools
- 可用的 Swift 工具链

### 2. 本地运行

```bash
swift build
swift run MangaGlass
```

### 3. 打包

```bash
./scripts/build_dmg.sh
```

产物位置：
- `dist/MangaGlass.dmg`

## 使用流程

1. 启动应用
2. 输入漫画链接或 slug
3. 选择站点镜像
4. 如有需要，填写 Cookie 或代理
5. 点击加载，确认分类和章节
6. 选择下载目录
7. 将章节加入队列并开始下载

## 主要功能

- 漫画目录解析
- 分类 / 卷 / 章节选择
- 批量下载
- 下载暂停、恢复、取消、失败重试
- 代理设置
- Cookie 注入
- 基础风控避让
- Copy 三镜像自动容灾

## 目录结构

```text
Sources/MangaGlass/
  App/        应用入口、窗口、主状态管理
  Models/     站点、漫画、代理等数据模型
  Services/   站点解析、下载调度、DOM 提取
  UI/         SwiftUI 界面
  Utils/      JSON、网络会话等通用工具
  Resources/  应用资源

scripts/
  build_dmg.sh  打包脚本
```

关键文件：
- `Sources/MangaGlass/App/MainViewModel.swift`
- `Sources/MangaGlass/Services/CopyMangaAPI.swift`
- `Sources/MangaGlass/Services/DownloadCoordinator.swift`
- `Sources/MangaGlass/Models/MangaModels.swift`

## 设计原则

- 优先可维护，不追求过度抽象
- 站点解析以稳定为先，不盲目提速
- 避免高频无效请求，降低风控概率
- 出现站点变更时，优先修解析链路，不扩大影响面

## 运行与维护说明

### 站点兼容性

本项目依赖第三方站点页面结构和接口字段。站点改版、风控增强、域名切换后，解析可能失效。

优先排查文件：
- `Sources/MangaGlass/Services/CopyMangaAPI.swift`
- `Sources/MangaGlass/Services/CopyRenderedDOMExtractor.swift`

### 风控说明

项目已实现基础节流、退避和镜像回退，但不能保证绝对不触发风控。

如果出现以下情况，优先判断为站点或网络问题：
- 403 / 429 / 503
- 页面返回维护页或伪 404
- 某个镜像连接重置或超时

### 下载输出

默认输出为按漫画 / 分类 / 章节组织的图片目录。具体路径由运行时选择。

## 常用命令

```bash
# 编译
swift build

# 运行
swift run MangaGlass

# 重新打包
./scripts/build_dmg.sh
```

## 已知边界

- 解析逻辑强依赖目标站点结构
- 不同镜像的稳定性可能不同
- 某些章节可能需要 Cookie 才能访问
- 某些镜像在特定网络下可能被封或被限速

## 许可与使用

本项目仅用于本地学习、研究和个人使用。

请仅访问和下载你有权访问的内容。使用者需自行承担由目标站点规则、版权或网络限制带来的风险。
