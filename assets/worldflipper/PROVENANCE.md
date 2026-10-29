# 《弹射世界》同人素材

本目录直接使用用户指定的《World Flipper / 世界弹射物语》原作像素、立绘与背景素材，版权为 **© Cygames, Inc. / Citail Inc.**，不是项目原创素材，也不属于旧素材的CC0声明。未发现这些原图的开放资产许可；本项目未声明取得官方同人游戏授权。原版权与来源声明见 [NOTICE.txt](NOTICE.txt)，官方来源见[权利表记](https://worldflipper.jp/copyright/)与[网站说明](https://worldflipper.jp/about/)。

阿尔克的角色设计、像素预览、完整立绘与技能动画从[BWIKI角色页](https://wiki.biligame.com/worldflipper/阿尔克)获取。运行时采用[角色动画收藏站](https://vivaldi6352.github.io/)保存的同一原作角色待机、前后步行GIF；保持原始24×30帧画布，以最近邻放大3倍，置于96×96单元的 `(12,3)`，脚底与当前游戏绘制包络相接。图集含1个待机帧、前后步行各4帧，步行保持原80／100／100／100毫秒时序。完整立绘现在保存至 `portraits/alk.png`，保留原始字节并用于封面独立肖像层；41帧技能GIF仅缓存供参考，不作为角色战斗循环。

五类敌人同样取自原作怪物的透明单帧姿态，保留当前游戏的64／64／80／72／160画布，按2／2／2／2／4倍最近邻放大。脚底固定在画布约91%处，与现有阴影对齐；原有移动起伏、受击压扁和状态染色继续作用于新图。这里只移植外观，敌人ID、名称、招式、血量、碰撞和刷怪规则继续使用当前游戏定义。

| 当前敌人ID | 原作图像 | 来源 |
| --- | --- | --- |
| chaser | 蓝波露 / Blue Blobble | [图鉴](https://wiki.biligame.com/worldflipper/蓝波露) |
| rusher | 帕拉鼠 / Zapquill | [图鉴](https://wiki.biligame.com/worldflipper/帕拉鼠) |
| tank | 魔像 / Golem | [图鉴](https://wiki.biligame.com/worldflipper/魔像) |
| caster | 火精 / Fire Imp | [图鉴](https://wiki.biligame.com/worldflipper/火精) |
| boss | 瑞西塔尔 / Regitare | [图鉴](https://wiki.biligame.com/worldflipper/瑞西塔尔) |

新封面底图来自[官方角色背景](https://worldflipper.jp/assets/images/top_char_bg.png)，以奶油底合成并等比裁成1280×720，无角色烘焙在底图中。右侧单独绘制完整阿尔克立绘，以线性过滤缩小且不裁头脚；像素角色和武器继续使用nearest。星芒循环由原生 `TitleCover` 的同一24帧状态捕获并编码为 `title/cover.gif`，元数据 `title/animation.json` 同时记录背景、立绘和绘制脚本SHA。旧 `assets/title/` 封面文件保留为历史资源。

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

[manifest.json](manifest.json) 记录每个原始URL、来源页、下载SHA-256、原尺寸、帧时长及最终文件校验。`tools/world_flipper_sources.json`、`world_flipper_enemies.json`、`world_flipper_cover_sources.json` 固定下载清单，`python tools/fetch_world_flipper_art.py --references` 下载、校验并生成17张运行图片；已有缓存时可加 `--offline` 重建。封面GIF需用 `tools/render_title_cover.gd` 捕获后，再运行 `tools/package_title_cover_gif.py` 编码。需要Python 3.10+和Pillow。多主角、选角与招募机制按用户要求留待后续讨论，当前仍以阿尔克作为主角。
