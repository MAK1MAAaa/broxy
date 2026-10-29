# 全屏动画封面来源

当前使用 `cover-alk.png`：内置 `image_gen.imagegen` 编辑下述原 `cover.png`，保留天空遗迹、石柱、金色天球环、烛台与右侧平台构图，以 `assets/worldflipper/portraits/alk.png` 为人物身份参考，将鸟喙巫师、浮空书和杖替换为阿尔克。它是AI编辑插画，不是未修改的原作立绘。原始生成结果及归一化校验保存在 `cover-alk.image-generation.json`；角色设计及参考立绘仍归 © Cygames, Inc. / Citail Inc.，权利与来源见[原作素材声明](../worldflipper/NOTICE.txt)。

`cover-alk.gif` 使用当前 `TitleCover` 原生24帧状态捕获，1280×720、120ms/帧、2.88秒无限循环，记录在 `cover-alk.animation.json`。游戏显示同一复合底图和离散动效，没有额外肖像叠加。以下旧鸟喙封面和旧元数据均保留原样，作为历史来源记录。

`cover.png` 是本轮内置 `image_gen.imagegen` 对原菜单插画的横向重构，保持鸟喙面具、青绿兜帽、骨杖、法典与黄金月环身份。原图生成尺寸1672×941，使用nearest规范到项目1280×720逻辑画布；未重画或篡改生成内容。提示词、参考路径与归一化方法见 `image-generation.json`。旧版 `assets/starfall/menu_art.png` 保留。

`scripts/ui/title_cover.gd` 原创绘制星尘、环光、火光和符印，按24个确定性帧状态循环，不移动整图、不扭曲角色、不消耗游戏随机数。`tools/render_title_cover.gd` 用相同原生绘制器捕获完整帧，`tools/package_title_cover_gif.py`仅以共享255色调色板及保留透明索引打包GIF，减少重复底图；颜色量化是GIF编码所需的格式转换。

`cover.gif` 是实际24帧、1280×720、120ms/帧、无限循环的GIF，完整周期2.88秒。帧来源与解码后图像SHA、底图及绘制器指纹记录在 `animation.json`。游戏以原生计时器和同一绘制状态播放，不依赖第三方GIF解码库；分发包同时包含原始GIF。

底图与GIF属于项目生成插画，适用生成服务的使用条款；本轮没有下载或嵌入第三方角色、Logo、图片、音频或字体。确定性绘制代码沿用项目原创源码的使用约定，不将AI底图误记为纯标准库程序美术。已有其他200个素材文件保持原字节。
