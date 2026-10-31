# 任务1：物品名称与图饰统一

任务1将武器显示名称、物品图标和实际战斗弹头接入同一目录，补齐结算、购前对照与奖励等低频入口。当前记录只覆盖这一项任务；后续的自选主角与两名后排、弹射地图机制和首领弱点战按独立任务交付。

## 名称与稳定ID

`ContentDef.display_name` 是界面名称来源，稳定ID继续用于背包、随机生成、符文、解锁和伤害统计。八件武器的当前名称如下；名称和外观沿用原作，攻击规则、价格、伤害、射程、冷却与物品占格沿用本游戏。

| 稳定ID | 当前显示名称 | 原作素材 |
| --- | --- | --- |
| bone | 野营刀 | Camping Knife |
| frost | 月之舞 | Moon Dance |
| ember | 怨嗟之杖 | Spiteful Staff |
| scatter | 海伯利安之弓 | Hyperion Bow |
| crescent | 悲叹死镰 | Grim Scythe |
| storm | 光芒龙典 | Lightcrest Tome |
| comet | 怨嗟逆枪 | Spiteful Spear |
| return_ring | 止战徽记 | Amulet of Ruin |

主菜单起始武器使用两列布局容纳完整名称；标题选择、商店商品、锁定状态、背包格、选中详情、合成目标、装符预览、HUD和环绕法器共用目录。遗物购前比较中的法器行和追猎者符文奖励同时显示对应图标。

结算页面按真实背包快照列出法器、遗物、松散符文和技能，保留实际阶级以及法器上的已装符文。伤害贡献按实际统计的武器ID显示名称和图标，已经出售的武器仍保留其累计伤害；不根据最终背包反推伤害来源。

## 原作素材与规范化

本次素材层版本为 `world-flipper-fan-04`。`assets/worldflipper/manifest.json` 包含49张规范化PNG与45条锁定来源记录；三个技能图标共用一张原图集，但分别保存精确裁片。五份源清单为：

- `tools/world_flipper_sources.json`：阿尔克与八件武器。
- `tools/world_flipper_enemies.json`：五类敌人。
- `tools/world_flipper_cover_sources.json`：保留的官方背景与原立绘。
- `tools/world_flipper_maps_sources.json`：四场景与三个道具。
- `tools/world_flipper_items_sources.json`：14遗物、3符文及3技能图标。

八件武器原图按3倍nearest居中置于64×64画布。新增 `assets/worldflipper/fx/projectile_heads.png` 将同一批图标按八种武器的既有顺序排列为512×64图集；`ProjectilePainter` 通过同一美术路由读取，因此飞行中的武器也能与商店、背包和HUD对应。图集保留透明像素和原色，碰撞与飞行逻辑不取图片外形。

14件遗物使用不同的原作饰品、护盾和书册像素，3符文使用原作能力魂Core图；所有裁片按3倍nearest置于64×64透明画布，保留原图的颜色、透明轮廓与自带光点。它们是本游戏的外观映射，遗物名称、属性、共鸣和符文机制仍使用本项目定义。逐项原作对应关系及来源链接见[素材来源](../assets/worldflipper/PROVENANCE.md)。

三个技能使用官方试玩道具图集里的 `ability_sphere_17/09/15`，分别对应秘术脉冲、落星和月弧。它们是无白色底板的原生20像素能力球，源PNG和atlas的SHA、帧名、裁切与3倍缩放记录在清单中；没有新增生成图或用同一张武器图重复填充缺口。

源码中的 `AdventureArt` 集中处理旧SVG身份到新PNG的映射，直接使用既有替代路径时保持幂等。旧资源作为历史素材保留，常规显示入口采用相同的新图；不在具体商品卡或背包格里维护第二份名称与图片列表。

## 重建、版权与验证

完整来源与原版权声明见[PROVENANCE](../assets/worldflipper/PROVENANCE.md)和[NOTICE](../assets/worldflipper/NOTICE.txt)。素材版权仍为 © Cygames, Inc. / Citail Inc.，原图未发现开放素材许可；Wiki正文许可不作为游戏图片许可，项目旧程序素材的CC0声明不适用于这些图片。

Windows完整门禁通过：97套测试和5个诊断入口共34528条断言，60项Python测试通过；原生与导出PCK各7套专项通过，5组固定截图逐像素一致。300敌人／600弹体／200掉落的60秒合成采样平均67.471 FPS、P99 20.270毫秒。Windows发行包已重建并启动，ZIP内10个文件逐字节核对通过；本轮未构建或运行macOS。结果与各日志指纹见[验收记录](../reports/world-flipper-catalog/validation.json)。

使用 `python tools/fetch_world_flipper_art.py --offline --references` 可从已校验的本地缓存重建整套规范化PNG。单独的 `python tools/world_flipper_items.py --offline` 重建20枚物品图标，处理器先校验完整输入族，再写输出；错误来源SHA、尺寸、裁片或倍数会拒绝处理。封面的AI编辑和GIF仍沿用独立的生成记录与捕帧流程。

本轮验证由 `reports/world-flipper-catalog/validation.json` 汇总，检查范围包括八种名称与目录身份、全部物品路由、真实购买／合成／装符及奖励入口、结算快照、战斗弹头、原图RGBA与整数像素、原生界面和导出包。实际执行结果以该记录为准；本文件不预填尚未完成的全量断言数、原生帧率或平台通过结论。
