# 《弹射世界》同人素材

本目录直接使用用户指定的《World Flipper / 世界弹射物语》原作像素素材，版权为 **© Cygames, Inc. / Citail Inc.**，不是项目原创素材，也不属于旧素材的CC0声明。未发现这些原图的开放资产许可；本项目未声明取得官方同人游戏授权。原版权与来源声明见 [NOTICE.txt](NOTICE.txt)，官方来源见[权利表记](https://worldflipper.jp/copyright/)与[网站说明](https://worldflipper.jp/about/)。

阿尔克的角色设计、像素预览、完整立绘与技能动画从[BWIKI角色页](https://wiki.biligame.com/worldflipper/阿尔克)获取。运行时采用[角色动画收藏站](https://vivaldi6352.github.io/)保存的同一原作角色待机、前后步行GIF；保持原始24×30帧画布，以最近邻放大3倍，置于96×96单元的 `(12,3)`，脚底与当前游戏绘制包络相接。图集含1个待机帧、前后步行各4帧，步行保持原80／100／100／100毫秒时序。完整立绘与技能GIF仅缓存于 `.tools/worldflipper/source/` 供用户参考，不作为角色战斗循环。

武器采用 [Wiki武器像素图](https://worldflipper.wiki.gg/wiki/Category:Armament_sprite_images) 中带透明背景的原图，最近邻放大3倍后居中放入64×64画布，不重画、不重新着色、不附加图鉴底纹。下表仅表示当前游戏的外观映射，不表示移植原作武器机制。

| 当前物品 | 原作素材 | 图鉴 |
| --- | --- | --- |
| 骨针 | Camping Knife | [图鉴](https://worldflipper.wiki.gg/wiki/Camping_Knife) |
| 霜矛 | Moon Dance | [图鉴](https://worldflipper.wiki.gg/wiki/Moon_Dance) |
| 幽焰 | Spiteful Staff | [图鉴](https://worldflipper.wiki.gg/wiki/Spiteful_Staff) |
| 散魂 | Hyperion Bow | [图鉴](https://worldflipper.wiki.gg/wiki/Hyperion_Bow) |
| 月镰 | Grim Scythe | [图鉴](https://worldflipper.wiki.gg/wiki/Grim_Scythe) |
| 雷灯 | Lightcrest Tome | [图鉴](https://worldflipper.wiki.gg/wiki/Lightcrest_Tome) |
| 星陨 | Spiteful Spear | [图鉴](https://worldflipper.wiki.gg/wiki/Spiteful_Spear) |
| 归魂环 | Amulet of Ruin | [图鉴](https://worldflipper.wiki.gg/wiki/Amulet_of_Ruin) |

[manifest.json](manifest.json) 记录每个原始URL、来源页、下载SHA-256、原尺寸、帧时长及最终文件校验。`tools/world_flipper_sources.json` 固定下载清单，`python tools/fetch_world_flipper_art.py --references` 下载、校验并生成；已有缓存时可加 `--offline` 重建。需要Python 3.10+和Pillow。武器和角色在原游戏的渲染层接入，商店、背包、HUD及环绕法器复用同一路由，游戏名称、物品ID、数值、碰撞与关卡规则保持现有内容。
