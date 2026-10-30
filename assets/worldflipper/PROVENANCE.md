# 《弹射世界》同人素材

本目录直接使用用户指定的《World Flipper / 世界弹射物语》原作像素、立绘与背景素材，版权为 **© Cygames, Inc. / Citail Inc.**，不是项目原创素材，也不属于旧素材的CC0声明。未发现这些原图的开放资产许可；本项目未声明取得官方同人游戏授权。原版权与来源声明见 [NOTICE.txt](NOTICE.txt)，官方来源见[权利表记](https://worldflipper.jp/copyright/)与[网站说明](https://worldflipper.jp/about/)。

阿尔克的角色设计、像素预览、完整立绘与技能动画从[BWIKI角色页](https://wiki.biligame.com/worldflipper/阿尔克)获取。运行时采用[角色动画收藏站](https://vivaldi6352.github.io/)保存的同一原作角色待机、前后步行GIF；保持原始24×30帧画布，以最近邻放大3倍，置于96×96单元的 `(12,3)`，脚底与当前游戏绘制包络相接。图集含1个待机帧、前后步行各4帧，步行保持原80／100／100／100毫秒时序。完整立绘保存至 `portraits/alk.png`，保留原始字节并作为新封面人物替换的身份参考；41帧技能GIF仅缓存供参考，不作为角色战斗循环。

五类敌人同样取自原作怪物的透明单帧姿态，保留当前游戏的64／64／80／72／160画布，按2／2／2／2／4倍最近邻放大。脚底固定在画布约91%处，与现有阴影对齐；原有移动起伏、受击压扁和状态染色继续作用于新图。火精与瑞西塔尔原GIF底部自带不透明的灰色接触影，本轮以原坐标和精确RGBA遮罩分别移除48／64个原生像素，并调整放置偏移保持身体脚底位置。没有对整张图片进行按颜色抠图，身体和黑色轮廓保留；其他三类敌人字节不变。此前敌人ID、名称、招式、血量和攻击规则沿用当前游戏，地面移动适配新障碍。本轮首领显示名统一为瑞西塔尔，接入本项目独立的蓄力、弱点与破防战斗；原作图像与本项目招式规则分别记录。

| 当前敌人ID | 原作图像 | 来源 |
| --- | --- | --- |
| chaser | 蓝波露 / Blue Blobble | [图鉴](https://wiki.biligame.com/worldflipper/蓝波露) |
| rusher | 帕拉鼠 / Zapquill | [图鉴](https://wiki.biligame.com/worldflipper/帕拉鼠) |
| tank | 魔像 / Golem | [图鉴](https://wiki.biligame.com/worldflipper/魔像) |
| caster | 火精 / Fire Imp | [图鉴](https://wiki.biligame.com/worldflipper/火精) |
| boss | 瑞西塔尔 / Regitare | [图鉴](https://wiki.biligame.com/worldflipper/瑞西塔尔) |

当前封面恢复项目原有天空遗迹场景，内置imagegen以原 `assets/title/cover.png` 为编辑目标、`portraits/alk.png` 为身份参考，只将右侧鸟喙人物、书和杖替换为阿尔克。它是基于原作角色参考的AI编辑图，不是未改动的官方原图。结果另存 `assets/title/cover-alk.png`，生成记录、归一化说明与24帧GIF见[封面来源](../title/PROVENANCE.md)。此前[官方角色背景](https://worldflipper.jp/assets/images/top_char_bg.png)及 `title/` 动图原样保留为历史资源，不再作为当前封面。

最初四张场景来自[官方试玩](https://worldflipper.jp/demo/)的战斗背景，映射沙漠遗迹、和风神社、魔界高塔和海盗船。原图为274像素宽的纵向弹射棋盘；本项目用较大的原生地面裁片以2倍nearest镜像拼接成3780×2192背景，原作边栏与拱门、鸟居天际、挑台和船桅均只放在活动范围以外，未将纵向整图横向拉伸，也不将适配后的场景称为完整原作地图。地形区域读取同一 `data/arenas.json`，用低对比度纹理变体标示既有减速范围。原图URL、SHA、尺寸、裁切、地标位置和输出SHA保存在 `tools/world_flipper_maps_sources.json` 与 `manifest.json`；新增顶外缘与完整资源契约见[弹射场景记录](../../docs/world-flipper-pinball.md)。

`world-flipper-fan-08` 再接入同一官方试玩的城镇街道、王座大厅和魔塔顶层，当前共七张素材主题竞技场。三张新图继续使用原色、2倍nearest地面裁片和活动区外原作地标，活动范围保持3444×1800；大厅红毯由原图中的地毯像素条镜像铺设，属于本项目构图。障碍、减速区和箱体由本项目配置，不把背景上绘出的装饰自动当作可碰撞机关。

| 游戏地图ID | 原作资源与原尺寸 | 官方原图 |
| --- | --- | --- |
| town | town_street，274×738 | [城镇街道背景](https://worldflipper.jp/demo/src/assets/production/battle/field/world_town/town_street/background/background.png) |
| throne | light_castle_throne，274×415 | [王座大厅背景](https://worldflipper.jp/demo/src/assets/production/battle/field/world_light/light_castle_throne/background/background.png) |
| tower_peak | evil_tower_top，769×274 | [魔塔顶层背景](https://worldflipper.jp/demo/src/assets/production/battle/field/world_evil/evil_tower_top/background/background.png) |

七张试玩素材主题不等于日服最终版地图全集。锁定的最终版 `field` 表中，沙漠、神社、海盗船可按完整背景资源key对应 `sand_ruins`、`japan_shrine`、`sea_ship_boss`；城镇背景对应多个活动条目及 `common_skill_preview`，覆盖追踪只登记后者的部分美术重构。试玩的 `evil_tower`、`light_castle_throne`、`evil_tower_top` 完整背景key不在该最终表内，保留为三个试玩专有的未映射场景，不编造日服场景ID。所有现有竞技场均未恢复原作关卡地形的1:1布局。

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

`world-flipper-fan-08` 新增下列八件原作武器的独立透明像素图，来源仍为Wiki的原生小图。22像素边长的原图使用2倍nearest，其余使用3倍nearest，以完整原始画布居中放入64×64，避免22×3超出画布；不使用带菱形底纹的96像素图、不抠背景、不重绘或重新着色。原图自带光点保留。八张独立PNG用于物品和弹头路由，原八件512×64弹头图集保持。

| 新武器ID | 日服原作装备ID | 当前名称与原作素材 | 整数缩放 |
| --- | --- | --- | --- |
| sword_0012 | 5010012 | 普罗米修斯之剑 / [Prometheus Blade](https://worldflipper.wiki.gg/wiki/Prometheus_Blade) | 2倍 |
| spear_0005 | 5030005 | 马尔特 / [Maltet](https://worldflipper.wiki.gg/wiki/Maltet) | 2倍 |
| sword_0004 | 5010004 | 天羽羽斩 / [Ame-no-Habakiri](https://worldflipper.wiki.gg/wiki/Ame-no-Habakiri) | 2倍 |
| axe_0009 | 5020009 | 雷神之锤 / [Thor's Hammer](https://worldflipper.wiki.gg/wiki/Thor%27s_Hammer) | 2倍 |
| book_0009 | 5050009 | 占事略决 / [Senji Ryakketsu](https://worldflipper.wiki.gg/wiki/Senji_Ryakketsu) | 3倍 |
| sword_0007 | 3010007 | 弯刀 / [Cutlass](https://worldflipper.wiki.gg/wiki/Cutlass) | 3倍 |
| axe_0024 | 5020024 | 帕拉修 / [Parashu](https://worldflipper.wiki.gg/wiki/Parashu) | 3倍 |
| sword_0011 | 5010011 | 海姆达尔之剑 / [Heimdall's Sword](https://worldflipper.wiki.gg/wiki/Heimdall%27s_Sword) | 2倍 |

身份按日服numeric ID、dev名与全球版英文装备名交叉核对；占事略决使用正确的古书原图，不使用名称相近的法杖。原图最终URL、SHA、原尺寸、完整画布裁切与缩放锁定在 `tools/world_flipper_weapon_expansion_sources.json`，规范化工具为 `tools/world_flipper_weapon_expansion.py`，缓存齐全时可用 `--offline` 重建。新增装备的投射攻击、球化／技能增幅、破防追击、回复及叠层数值为本作改编；图片与身份来源不构成原作全部装备能力已经移植的声明。

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

任务1的三个能力球图标取自[官方试玩道具图集](https://worldflipper.jp/demo/src/assets/production/item/sprite_sheet.png)：`skill_pulse` 使用 `ability_sphere_17`，`skill_starfall` 使用 `ability_sphere_09`，`skill_arc_slash` 使用 `ability_sphere_15`。原生20×20裁片分别为 `(25,221,20,20)`、`(26,27,20,20)`、`(25,173,20,20)`，均按3倍nearest居中放置；对应[atlas](https://worldflipper.jp/demo/src/assets/production/item/sprite_sheet.atlas.json)的SHA与帧名也写入来源清单。这三张PNG作为历史素材保留，当前技能路由改为克拉莉丝、花火、希尔媞的原作待机像素；三名角色的动画、完整立绘与规范化说明集中于[队伍素材记录](../../docs/world-flipper-party.md)。

新增球、木桶、宝箱、回复瓶、充能瓶和mana同样使用[官方试玩](https://worldflipper.jp/demo/)原图，逐项来源与所用atlas条目保存在 `tools/world_flipper_interactions_sources.json`。球与木桶恢复原裁剪和旋转帧后按共同画布排图；透明像素和原色保留，球0.48秒循环与木桶0.32秒破碎为本项目明确适配，不声明原作FPS或完整原动画。宝箱保留完整22×20原图，回复瓶与充能瓶取13×19有效帧，mana选12×12静态a面；详情见[交互图片契约](../../docs/world-flipper-pinball.md)。

首领弱点使用同一[官方试玩通用战斗UI图集](https://worldflipper.jp/demo/src/assets/production/battle/common/layer1.png)中的 `boss_weak_point_sight` 与 `boss_weak_point_broken`，原PNG、atlas、parts和timeline的SHA及实际裁片、矩阵保存在 `tools/world_flipper_weakpoints_sources.json`。完整标靶先恢复原39×39象限画布，再以四向旋转组合圆环和四条原30×18十字臂；没有将单个四分之一圆当作完整弱点。运行图集 `boss/weakpoint-atlas.png` 为288×96，三个96单元依次为白色、红色和破坏状态，中心统一 `(48,48)`。破坏状态采用原parts的四弧片、四条片及0.66缩放快照，验证全片不越界后归入96画布。内圈按偶数68像素居中；红白闪烁、蓄力切换、破坏时长与弱点规则为本游戏适配，不声明复制原作FPS、完整插值或首领机制。布局与适配说明独立保存于 `boss/weakpoint-art.json`。原BossHP裁片仅为代码伸缩用白条，本轮没有为此增加发行PNG或说明文案。

[manifest.json](manifest.json) 当前版本为 `world-flipper-fan-08`，记录每个原始URL、来源页、下载SHA-256、原尺寸、帧时长及最终文件校验。由九份清单锁定82条来源记录：`tools/world_flipper_sources.json`、`world_flipper_enemies.json`、`world_flipper_cover_sources.json`、`world_flipper_maps_sources.json`、`world_flipper_items_sources.json`、`world_flipper_heroes.json`、`world_flipper_interactions_sources.json`、`world_flipper_weakpoints_sources.json`、`world_flipper_weapon_expansion_sources.json`。其中三个能力球共用同一原图集、保留各自裁片记录。`python tools/fetch_world_flipper_art.py --references` 下载、校验并生成79张规范化PNG，包含保留的历史封面背景与原立绘，并另存交互及弱点两份运行元数据JSON；原65张PNG保持字节不变。已有缓存时可加 `--offline` 重建。弱点也可单独运行 `python tools/world_flipper_weakpoints.py --offline` 重建。当前封面GIF需用 `tools/render_title_cover.gd` 捕获后，再运行 `tools/package_title_cover_gif.py` 编码，AI底图保留生成记录，不参与公开源离线重建。需要Python 3.10+和Pillow。各任务的实现与实际验证范围见[目录统一记录](../../docs/world-flipper-catalog.md)、[队伍记录](../../docs/world-flipper-party.md)和[弹射场景记录](../../docs/world-flipper-pinball.md)。

全量内容的事实索引另锁定公开日服归档 [blead/wf-assets](https://github.com/blead/wf-assets/tree/1d45b529ef078ba9b1f876d4588debd0c8a9a214)，提交为 `1d45b529ef078ba9b1f876d4588debd0c8a9a214`，数据版本 `1.780.40`，归档提交时间为2024-02-19 17:09 UTC，早于官方2024-02-20停止在线服务。`tools/world_flipper_catalog_sources.json` 锁定13份原始表／资产树的URL、字节数与SHA；原始大文件留在本地 `.tools/worldflipper/catalog/raw/`，规范化结果为 [catalog.json](../../data/worldflipper/catalog.json)。索引保留505个角色版本、426件装备、570组／1062个主动技能等级变体、6组切换技能、247个场景、1422个地形布局、89组挑战副本原始配置和12个主线章节；季节与联动版本保留各自原作ID。所有1062个技能变体的动作引用均能对应固定资产树中的指令文件，但索引本身不包含全部图片、地形二进制，也不会将未知位置字段解释成已实现规则。

可运行 `python tools/import_world_flipper_catalog.py --offline --check` 核对离线重建；首次取得原始缓存时去掉 `--offline`。原作技能能量保留原始列值和单位，不当作本作冷却秒数。角色、装备、技能、场景与原关卡布局的逐项进度由 [implementation.json](../../data/worldflipper/implementation.json) 跟踪，`python tools/audit_world_flipper_coverage.py` 校验来源和全部待实现ID；仅收录目录、接入图片、部分改编与运行验证分别记录。素材离线重建不代表全量玩法或性能验收完成，剩余内容与实际性能结果继续以项目实现和验证报告为准。该公开归档同样未提供原作资产的开放许可，不能把归档公开视为授权。

本轮追加三份原作关卡裁片与墙线，使用独立[stages清单](stages/manifest.json)，记录12个实际使用来源与6张PNG；原79张PNG和fan08清单保留。固定JP原始动作、装备能力表、官方demo地形和2022动画镜像分别由 `tools/world_flipper_skill_action_sources.json`、`world_flipper_equipment_rules_sources.json`、`world_flipper_layout_sources.json`、`world_flipper_character_animation_sources.json` 追踪。1122份GIF只在本地缓存，未作为374名新主角发行；131份角色版本缺口明示保留。指令及资源引用已取得不等于全部技能或原关卡已移植，详见[本轮实现和限制](../../docs/world-flipper-actions.md)。

本轮追加娜希尔、莫迪亚迦、法露伽的原作待机与双向步行像素规范化，独立清单位于 assets/worldflipper/roster/manifest.json；像素portrait并非原作全身立绘。132份历史背景仅作本地来源准备，未作为额外可玩布局。原作角色、背景、图像与数据版权归 Cygames, Inc. / Citail Inc.，未发现开放资产许可；当前为用户指定同人用途。
