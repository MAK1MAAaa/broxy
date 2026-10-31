# Fusion Pixel 游戏字体

- 项目：[Fusion Pixel Font](https://github.com/TakWolf/fusion-pixel-font)，作者 TakWolf。
- 官方版本：[2026.10.25](https://github.com/TakWolf/fusion-pixel-font/releases/tag/2026.10.25)。
- 原始下载：[12px proportional OTF 压缩包](https://github.com/TakWolf/fusion-pixel-font/releases/download/2026.10.25/fusion-pixel-font-12px-proportional-otf-v2026.10.25.zip)。
- 压缩包 SHA-256：`e77c009a993cf220eb6d5d94ca69ff3325f72ac063a0e4bd8aae32028c5acb93`。
- 包内字体：`fusion-pixel-12px-proportional-zh_hans.otf`，即 Fusion Pixel 12px Prop zh-Hans Regular。
- 游戏文件：`fusion-pixel-12px-proportional-zh-hans.otf`。仅调整文件名，字体字节完整保留，没有裁字或修改字形。
- 字体 SHA-256：`2972782f05d7dd5f8414bc0215f69c181561172286b1f9823b5c279d9e5e6674`。

字体按 SIL Open Font License 1.1 分发。`licenses/fusion-pixel/OFL.txt` 保留该版本的完整版权与许可文本；`licenses/fusion-pixel/LICENSES/` 原样保留发布包附带的 Ark Pixel、Cubic 11（含其上游字体声明）及 Galmuri 许可。分发游戏时，应将整个 `licenses/fusion-pixel/` 目录一并放入发行包的 `licenses/fonts/`，保留原始版权和许可文本。

`GameTypography.font()` 提供共享字体资源，关闭系统字体回退、抗锯齿、hinting 和亚像素定位，`oversampling = 1.0`；`size_for()` 将界面字号限制在 12、24、36、48，保持基础像素的整数倍。OTF 按目标字号直接栅格化，不额外设置 `fixed_size`。

属性与枚举依据：[Godot FontFile](https://docs.godotengine.org/en/stable/classes/class_fontfile.html)、[Godot TextServer](https://docs.godotengine.org/en/stable/classes/class_textserver.html)。`oversampling = 0.0` 会继承视口设置，因此显式使用 `1.0`。
