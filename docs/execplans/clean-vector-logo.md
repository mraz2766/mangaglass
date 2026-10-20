# ExecPlan：重新设计干净的矢量 Logo

## 摘要

用户要求重新设计 Logo 并替换，「干净一点」。原手绘蜡笔小象细节多（纹理、腮红、四肢、尾巴、复杂枝叶），小尺寸发糊。新稿保留品牌故事（小象 + 嫩芽），改为扁平几何造型，配合 1.12 经典主题的白蓝玻璃风格。

## 设计

- 白色圆头侧脸 + 内嵌浅蓝耳朵 + 上扬象鼻 + 单株绿芽（两片叶），深蓝圆点眼。
- macOS 图标网格：824 px 圆角方块居中、外留 100 px，带系统风格投影；方块为蓝色竖向渐变 + 顶部柔光 + 内描边，形成玻璃感。
- 应用内 Logo 用无外边距的满版版本（`mark`），图标集用带外边距和投影的版本（`tile`）。
- 每个尺寸都由矢量直接绘制，不做位图缩放。

## 修改文件

- `scripts/draw_logo.swift`（新增，Logo 矢量源）
- `assets/logo.png`、`Sources/MangaGlass/Resources/logo.png`
- `assets/AppIcon.iconset/*`、`assets/AppIcon.icns`
- `scripts/build_app.sh`（版本）

## 约束

- 品牌资源更新，普通修改：`1.12.0` → `1.12.1`。

## 结果

- 16–1024 px 全尺寸重绘，`iconutil` 生成 ICNS；侧栏快照确认新 Logo 显示正常。
- 已构建并替换 `/Applications/MangaGlass.app`。
