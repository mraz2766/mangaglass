# ExecPlan：重写中英文 README

## 摘要

两份 README 停留在旧版本：仍描述已移除的代理设置、顶栏「清缓存」、旧「下载管理」，列出已不支持的 MYCOMIC，截图是旧界面。本次按 1.12.1 的真实代码重写，并生成新截图。只改文档与测试中的截图渲染，不改应用行为，不递增版本。

## 范围

- `README.md`（英文）、`README.zh-CN.md`（中文）：结构一致，内容对齐代码事实。
- `assets/screenshots/*`：由 `testRenderReadmeShowcase` 用虚构示例数据渲染（无真实作品名或封面）。
- 删除过期的 `assets/home.png`。
- `Tests/MangaGlassTests/LayoutSnapshots.swift`：新增可选的 README 截图渲染（需设置 `MANGAGLASS_README_DIR`）。

## 已确认事实

- 支持站点：拷贝漫画（mangacopy / 2026copy / copy4000）、漫画柜、包子漫画；无 MYCOMIC。
- 无代理设置界面；`URLSession.default` 遵循系统代理。
- 选择：⇧ 连选、⌘ 追加、拖框；卷级全选按钮。
- 分组目录仅在所选章节跨多个分组时创建；图片命名 `漫画名[-分组]-章节-0001.jpg`。
- 下载完成发送系统通知；下载期间不会阻止系统睡眠（仅 App Nap 相关），README 不作此承诺。

## 结果

- 两份 README 重写完成，所有图片路径校验存在。
- 发现 `scripts/build_dmg.sh` 版本号仍为 1.3.3，未在本次修改，已告知用户。
