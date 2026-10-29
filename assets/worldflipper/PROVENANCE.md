# 《弹射世界》同人素材

本目录直接使用用户指定的《World Flipper / 世界弹射物语》原作像素、立绘与背景素材，版权为 **© Cygames, Inc. / Citail Inc.**，不是项目原创素材，也不属于旧素材的CC0声明。未发现这些原图的开放资产许可；本项目未声明取得官方同人游戏授权。原版权与来源声明见 [NOTICE.txt](NOTICE.txt)，官方来源见[权利表记](https://worldflipper.jp/copyright/)与[网站说明](https://worldflipper.jp/about/)。

阿尔克的角色设计、像素预览、完整立绘与技能动画从[BWIKI角色页](https://wiki.biligame.com/worldflipper/阿尔克)获取。运行时采用[角色动画收藏站](https://vivaldi6352.github.io/)保存的同一原作角色待机、前后步行GIF；保持原始24×30帧画布，以最近邻放大3倍，置于96×96单元的 `(12,3)`，脚底与当前游戏绘制包络相接。图集含1个待机帧、前后步行各4帧，步行保持原80／100／100／100毫秒时序。完整立绘保存至 `portraits/alk.png`，保留原始字节并作为新封面人物替换的身份参考；41帧技能GIF仅缓存供参考，不作为角色战斗循环。

五类敌人同样取自原作怪物的透明单帧姿态，保留当前游戏的64／64／80／72／160画布，按2／2／2／2／4倍最近邻放大。脚底固定在画布约91%处，与现有阴影对齐；原有移动起伏、受击压扁和状态染色继续作用于新图。火精与瑞西塔尔原GIF底部自带不透明的灰色接触影，本轮以原坐标和精确RGBA遮罩分别移除48／64个原生像素，并调整放置偏移保持身体脚底位置。没有对整张图片进行按颜色抠图，身体和黑色轮廓保留；其他三类敌人字节不变。敌人ID、名称、招式、血量和攻击规则沿用当前游戏，地面移动适配新障碍。

| 当前敌人ID | 原作图像 | 来源 |
| --- | --- | --- |
| chaser | 蓝波露 / Blue Blobble | [图鉴](https://wiki.biligame.com/worldflipper/蓝波露) |
| rusher | 帕拉鼠 / Zapquill | [图鉴](https://wiki.biligame.com/worldflipper/帕拉鼠) |
| tank | 魔像 / Golem | [图鉴](https://wiki.biligame.com/worldflipper/魔像) |
| caster | 火精 / Fire Imp | [图鉴](https://wiki.biligame.com/worldflipper/火精) |
| boss | 瑞西塔尔 / Regitare | [图鉴](https://wiki.biligame.com/worldflipper/瑞西塔尔) |

当前封面恢复项目原有天空遗迹场景，内置imagegen以原 `assets/title/cover.png` 为编辑目标、`portraits/alk.png` 为身份参考，只将右侧鸟喙人物、书和杖替换为阿尔克。它是基于原作角色参考的AI编辑图，不是未改动的官方原图。结果另存 `assets/title/cover-alk.png`，生成记录、归一化说明与24帧GIF见[封面来源](../title/PROVENANCE.md)。此前[官方角色背景](https://worldflipper.jp/assets/images/top_char_bg.png)及 `title/` 动图原样保留为历史资源，不再作为当前封面。

四张场景来自[官方试玩](https://worldflipper.jp/demo/)的战斗背景，映射沙漠遗迹、和风神社、魔界高塔和海盗船。原图为274像素宽的纵向弹射棋盘；本项目截取干净地面并以2倍nearest、镜像拼接扩成3780×2104背景，原作边栏只放在活动范围以外，未将纵向整图横向拉伸。地形区域读取同一 `data/arenas.json`，用低对比度纹理变体标示既有减速范围。原图URL、SHA、尺寸、裁切和输出SHA保存在 `tools/world_flipper_maps_sources.json` 与 `manifest.json`。

石碑、花坛和弹板来自同一官方试玩的field_object图集，按对应atlas帧排除1像素边栏，分别最近邻放大4／3／3倍，放入96×96透明画布，脚点统一在 `(48,84)`。原色和轮廓不变。运行时按配置半径显示并阻挡地面角色、敌人、冲刺和击退；飞行弹体可以越过这些低矮障碍。地图改用原场景主题，活动尺寸、原34处地形坐标和减速倍率保持，障碍位置为本项目重新布置。

武器采用 [Wiki武器像素图](https://worldflipper.wiki.gg/wiki/Category:Armament_sprite_images) 中带透明背景的原图，最近邻放大3倍后居中放入64×64画布，不重画、不重新着色、不附加图鉴底纹。任务1将显示名称统一到下表，稳定ID与当前游戏的攻击参数保持；使用原作品名和图片，不表示移植原作武器机制。

| 稳定ID | 当前显示名称 | 原作素材 |
| --- | --- | --- |
| bone | 野营刀 | [Camping Knife](https://worldflipper.wiki.gg/wiki/Camping_Knife) |
| frost | 月之舞 | [Moon Dance](https://worldflipper.wiki.gg/wiki/Moon_Dance) |
| ember | 怨嗟之杖 | [Spiteful Staff](https://worldflipper.wiki.gg/wiki/Spiteful_Staff) |
| scatter | 海伯利安之弓 | [Hyperion Bow](https://worldflipper.wiki.gg/wiki/Hyperion_Bow) |
| crescent | 悲叹死镰 | [Grim Scythe](https://worldflipper.wiki.gg/wiki/Grim_Scythe) |
| storm | 光芒龙典 | [Lightcrest Tome](https://worldflipper.wiki.gg/wiki/Lightcrest_Tome) |
| comet | 怨嗟逆枪 | [Spiteful Spear](https://worldflipper.wiki.gg/wiki/Spiteful_Spear) |
| return_ring | 止战徽记 | [Amulet of Ruin](https://worldflipper.wiki.gg/wiki/Amulet_of_Ruin) |

八件规范化武器原图同时按 `bone / frost / ember / scatter / crescent / storm / comet / return_ring` 顺序放入 `fx/projectile_heads.png`，每格64×64，整图512×64。弹头沿用图标的原始透明像素，不再使用另一套外观；飞行轨迹、碰撞半径、符文和伤害仍取本游戏的战斗数据。

14件遗物的透明像素来自同一Wiki的不同原作装备，分别规范为64×64、3倍nearest。原作图片中自带的光点保留，没有添加文字、底板或重绘。下表是本游戏遗物的独立外观映射：遗物名称、属性和相邻共鸣仍由本项目定义，不等同于原作装备能力。

| 遗物ID | 当前名称 | 原作图片 |
| --- | --- | --- |
| damage | 血棘 | [Beared Fang](https://worldflipper.wiki.gg/wiki/Beared_Fang) |
| haste | 时砂 | [Protostar Belt](https://worldflipper.wiki.gg/wiki/Protostar_Belt) |
| speed | 夜行靴 | [Seaside Ribbon](https://worldflipper.wiki.gg/wiki/Seaside_Ribbon) |
| vitality | 心瓮 | [Luna Womb](https://worldflipper.wiki.gg/wiki/Luna_Womb) |
| armor | 黑曜甲 | [Spiteful Cloak](https://worldflipper.wiki.gg/wiki/Spiteful_Cloak) |
| magnet | 引魂铃 | [Earrings of Amity](https://worldflipper.wiki.gg/wiki/Earrings_of_Amity) |
| moon_charm | 月蚀吊坠 | [Spiteful Necklace](https://worldflipper.wiki.gg/wiki/Spiteful_Necklace) |
| pilgrim | 巡礼靴 | [Ebony Handbag](https://worldflipper.wiki.gg/wiki/Ebony_Handbag) |
| bulwark | 骨盾印 | [Aero Bone Shield](https://worldflipper.wiki.gg/wiki/Aero_Bone_Shield) |
| hourglass | 裂砂漏 | [Polychromatic Earrings](https://worldflipper.wiki.gg/wiki/Polychromatic_Earrings) |
| blood_pact | 血契书 | [Dream Journal](https://worldflipper.wiki.gg/wiki/Dream_Journal) |
| grave_candle | 引魂烛 | [Lightcrest Crown](https://worldflipper.wiki.gg/wiki/Lightcrest_Crown) |
| fold_clasp | 折影扣 | [Square Glasses](https://worldflipper.wiki.gg/wiki/Square_Glasses) |
| echo_stone | 回响石 | [Savant's Doll](https://worldflipper.wiki.gg/wiki/Savant%27s_Doll) |

三个符文采用 [Wiki能力魂像素图](https://worldflipper.wiki.gg/wiki/Category:Armament_Core_sprite_images)：`pierce` 对应 Wrist-Mounted Catapult (Core)，`bounce` 对应 Protostar Shield (Core)，`blast` 对应 Aero Bomb Bag (Core)。它们使用三个不同的原图，按3倍nearest置入64×64透明画布，贯穿、弹射和爆破的触发规则沿用本游戏。

三个技能图标取自[官方试玩道具图集](https://worldflipper.jp/demo/src/assets/production/item/sprite_sheet.png)中的透明像素能力球：`skill_pulse` 使用 `ability_sphere_17`，`skill_starfall` 使用 `ability_sphere_09`，`skill_arc_slash` 使用 `ability_sphere_15`。原生20×20裁片分别为 `(25,221,20,20)`、`(26,27,20,20)`、`(25,173,20,20)`，均按3倍nearest居中放置；对应[atlas](https://worldflipper.jp/demo/src/assets/production/item/sprite_sheet.atlas.json)的SHA与帧名也写入来源清单。没有采用带白色卡片底的dynamic技能UI图，也没有把这些能力球记为角色肖像。

[manifest.json](manifest.json) 记录每个原始URL、来源页、下载SHA-256、原尺寸、帧时长及最终文件校验。当前由五份清单锁定45条来源记录：`tools/world_flipper_sources.json`、`world_flipper_enemies.json`、`world_flipper_cover_sources.json`、`world_flipper_maps_sources.json`、`world_flipper_items_sources.json`。其中三个能力球共用同一原图集、保留各自裁片记录。`python tools/fetch_world_flipper_art.py --references` 下载、校验并生成49张规范化PNG，包含保留的历史封面背景与原立绘；已有缓存时可加 `--offline` 重建。当前封面GIF需用 `tools/render_title_cover.gd` 捕获后，再运行 `tools/package_title_cover_gif.py` 编码，AI底图保留生成记录，不参与公开源离线重建。需要Python 3.10+和Pillow。当前任务1为物品目录统一，主角仍为阿尔克；自选主角、两名后排角色与R技能按后续独立任务实现与验收。实现与本轮验证范围见[目录统一记录](../../docs/world-flipper-catalog.md)。
