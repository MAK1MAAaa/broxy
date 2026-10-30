# 原作动作与关卡布局（前轮记录）

本文保留commit12a7a21的四主角／十图验收范围；后续三角色与解码增量见[角色技能持续扩充](world-flipper-roster.md)。

本轮继续日服最终版全目录目标，补上原始动作、装备能力和地形数据的可追踪入口，并把已确认的四主角时序与三份原作布局接入当前游戏。当前可玩内容仍是四位主角、十六件武器及十张竞技场。目录、源文件、已解码规则、实际运行和完整移植分别记录，不能互相替代。

## 固定来源与剩余范围

日服归档固定在 `blead/wf-assets@1d45b529ef078ba9b1f876d4588debd0c8a9a214`，版本1.780.40。

- 1062条技能变体对应1019份根动作和8份递归子动作。1027个文件的Git blob、SHA256及字节数均锁定。提取55种指令、1639个命中区，保留原始时间、形状、命中策略和JSON Pointer。`CalculatedUsingMaxNumOfHits`与直接指定间隔、固定寿命与等级寿命分别保存，未知参数不猜含义。
- 426件装备通过原表的能力引用关联886条123列规则；29件增强装备另有108条126列规则。旧八件的21条原始规则有语义映射，其余865条仍明确未解码。该提取没有自动把装备塞入商店，也没有为未实现装备生成通用投射物；两件原标记为不可玩的剧情装备单独保留身份。
- 8份可下载的官方试玩地形，包含11个独立层、259个对象及176条开放墙段。只有3份地形资源引用精确匹配最终日服目录，另外5份是试玩教程。归档仅提供地形引用，无法据此证明试玩文件与最终客户端二进制逐字节相同，不能声称已还原全部1422个布局。
- 固定2022-08-09动画镜像 `vivaldi6352.github.io@24935f8731f134cb9ec6da9c126ca38ae8c8ae1f` 覆盖374/505个角色版本，1122份原GIF总约3.53MB。待机和两种行走均验证真实帧、透明度和原始时长；行走不是待机复制。其余131个版本缺少精确路径，未借用其他版本或生成替代图。该批GIF只进入本地素材准备缓存，没有把374名角色计入已实装主角。

规范化数据位于 `data/worldflipper/skill_actions.json`、`equipment_rules.json`、`layouts.json`；来源清单分别位于 `tools/`。原文件、大型结构报告和GIF留在 `.tools/`，不进入源码或发行包。全部待办和差异继续由 [implementation.json](../data/worldflipper/implementation.json) 跟踪。

```powershell
python tools/world_flipper_skill_actions.py --offline --check
python tools/world_flipper_equipment_rules.py --offline --check
python tools/world_flipper_layouts.py --offline
python tools/fetch_world_flipper_character_animations.py --offline --check
python tools/world_flipper_stages.py
python tools/audit_world_flipper_coverage.py
```

## 当前主角的真实时序

原动作时间值明确按“1单位映射为本作1/60秒”适配；这不是已证实的原作FPS。范围、伤害、增益和冷却继续使用本游戏数值。四个资源保留实际动作引用、固定Git blob及适配说明。

| 主角 | 当前行为 |
| --- | --- |
| 阿尔克 | 施放时立即获得20%攻击强化、持续5秒；44单位前摇后在当前位置建立20单位的周围火伤区，每个目标只中一次。保留自由移动及角色可见性，不复制原作停球和隐藏角色指令。 |
| 克拉莉丝 | 前方42单位后开启4击区，79单位后开启11击区，按原两段倍率权重分配基础伤害；实际命中后才施加火易伤。独立104单位驱散区对每个目标只移除一个受支持的临时正面状态。施放时获得火属性技伤强化25%、持续5秒，影响对应技能、不强化普通武器或风技能。 |
| 希尔媞 | 25单位前摇后建立31单位的前后狭长矩形；本作720×48与原3000×200保持相同比例。每UID一次，施放时锁定实际球化连击增伤。 |
| 花火 | 先预约五个炸弹和五个爆区槽位，55单位后从主角当前位置发射。实际碰撞或寿命结束才激活30单位的持续单击爆区；晚到的目标可以被命中，同一爆区不会重复命中同UID。飞行速度、寿命和扇形散布仍是本作适配，不伪称来自动作脚本。 |

持续区域按目标记录命中上限和接触间隔，离区清除下一次接触时钟，不补算离开期间的伤害；敌人池槽位复用必须以新UID重新判断。炸弹提前预约爆区，避免到达时覆盖其他效果或无声丢失伤害。预约失败不消耗施放、冷却或增益。

伤害信号回调同步击杀或替换敌人时，后续处理再次校验UID与存活状态，释放槽位保持幂等，避免重复击杀、重复奖励及重复可用槽位。易伤按实际命中的到期时间结算；跨越整个技能窗口的大步长不会留下刚刷新的易伤，非整倍跨步与60Hz的命中次数、伤害及最终剩余时长有独立对照。

时间轴固定24区、炸弹固定20枚、爆炸回执固定20项。暂停冻结，停止、终局和新波清理。绘制直接读取真实前摇、区域和爆点，不再提前画瞬时命中；关闭闪光保留必要轮廓，敌方危险预警继续置顶。临时敌人强化支持攻击、速度、减伤三类，使用金色角标表达；驱散后反馈来自实际状态移除。尚未新增敌人施加这些强化的自然波次招式，不能把夹具中的驱散验证当作完整敌人生态。

仍未完成：完整原作强化种类、队长与角色能力、原作等级成长、全队命中连击、协力球弹板反射，以及三个旧背包后排与新版R的统一。季节、周年和联动角色仍按各自ID继续扩充。

## 三份可玩的原布局

| 本作地图ID | 原布局 | 背景资源 | 接入层 | 真实墙段 |
| --- | --- | --- | ---: | ---: |
| jp_sand_2_9_5 | main_2_9_5 | sand_ruins | 0 | 3 |
| jp_shrine_6_6_2 | main_6_6_2 | japan_shrine | 0 | 6 |
| jp_ship_3_6_2 | main_3_6_2 | sea_ship_boss | 0 | 8 |

使用原BOUNDS裁片做4倍nearest像素图，逻辑坐标统一缩放2/3，保持图像和墙体对齐。将BOUNDS用作本作720×1280可活动矩形属于明确的竞技场适配，不宣称已证实其原作物理用途。外部暗底与边框只承担画面留白。旧七张3444×1800竞技场和79张原PNG字节保持，新六张PNG由独立的 [场景素材清单](../assets/worldflipper/stages/manifest.json) 追踪。

WALL只连接原polyline相邻顶点，不补首尾闭合；实体以真实线段胶囊扫掠、端点圆帽、滑动和绕端点路线处理。出生、Boss、弱点和击退使用本图边界；冲刺撞原墙可触发当前游戏的球化反弹。摄像机保留HUD空间，小地图按竖向真实范围显示墙线。旧七图的碰撞、箱体及地形规则保留。

原道具只保留位置来源；碰撞尺寸、互动和机关定义未知时不以编辑器椭圆或通用12箱替代。教程层0/1独立保存，不能合并成一张墙网。剩余1419个日服布局及全部原作关卡敌人配置仍待推进。

## 原生验证入口

```powershell
./tools/run.ps1 --script res://tools/preview_skill_timelines.gd -- --hero=clarisse --view=second --arena=throne --capture=D:/Github/broxy/reports/world-flipper-actions/clarisse-second.png
./tools/run.ps1 --script res://tools/preview_skill_timelines.gd -- --view=bomb-late --arena=throne --capture=D:/Github/broxy/reports/world-flipper-actions/bomb-late.png
./tools/run.ps1 --script res://tools/preview_skill_timelines.gd -- --view=map --arena=jp_ship_3_6_2 --capture=D:/Github/broxy/reports/world-flipper-actions/original-ship.png
./tools/run.ps1 --script res://tools/preview_skill_timelines.gd -- --view=map --arena=jp_ship_3_6_2 --region=south --capture=D:/Github/broxy/reports/world-flipper-actions/original-ship-south.png
./build/Embers-windows-x86_64/Embers.exe -- --wf-actions-preview --view=map --arena=jp_ship_3_6_2 --region=south --capture=D:/Github/broxy/reports/world-flipper-actions/release-ship-south.png
./tools/run.ps1 --script res://tools/benchmark_dash.gd -- --seconds=60 --hero=hanabi --hero-skills --backpack-skills --pinball-probes --evasion-probes --output=res://reports/world-flipper-actions/performance-hanabi.json
```

预览使用真实排队施放和60Hz固定步，只有目标血量、移动及自动射击由明确夹具控制；不是自然通关或平衡验收。两次实际绘制前后比较完整战斗状态和三路随机流。手柄提示使用合成输入，不等于硬件验收。

状态比对包含区域的命中次数、下一次接触时钟、预约槽位、炸弹与爆区的关联以及真实墙段。源码原生窗口、导出PCK及实际发行EXE分别验证；发行预览明确记录`debug_build=false`，防止编辑器中的成功掩盖发布版跳过`assert`的差异。墙体配置独立执行，断言只检查结果。

发行模板禁用外部脚本／项目路径覆盖，因此外部测试套件通过原生引擎加载发行PCK执行。真正的EXE使用`--wf-actions-preview`进入内置诊断节点，工具入口也启动同一节点；在读取个人存档前关闭持久化，子场景带内部标记避免递归。正常启动路径不受影响。

完整入口仍为 `./tools/test.sh`，Windows入口同步122套件。最终证据记录在 `reports/world-flipper-actions/validation.json`；原截图和日志保留本地。更新前Windows包备份为 `build/Embers-windows-before-actions-e8f0d27.zip`，SHA256与上一轮发行记录吻合。macOS未在本Windows主机上构建或运行。

## 本轮验收

`./tools/test.sh`通过122套件与5个诊断调用，共71,207项Godot断言及155项Python测试；最终账本绑定后另复核12项覆盖审计测试。源码与导出PCK各通过22项原生检查。24组预览覆盖三图的中央／南北边界、四主角前摇与首段、克拉莉丝第二段和驱散、花火飞行／碰撞爆发／晚到目标、小窗口手柄提示及关闭闪光；源码、PCK与真正发行EXE的像素及战斗状态全部一致，发行侧均确认`debug_build=false`。旧79张PNG及其清单保持原字节，新增6张场景PNG由独立清单校验。

四组原生压力采样各60秒，均保持300敌人、600弹体、200掉落的逐物理步负载下限，使用真实Q／E／R与冲刺／球化探针。门槛为平均至少58 FPS、P99不超过33毫秒。

| 主角 | 合法后排 | 平均FPS | P99毫秒 |
| --- | --- | ---: | ---: |
| 阿尔克 | 花火、希尔媞 | 63.550 | 26.128 |
| 克拉莉丝 | 花火、希尔媞 | 62.017 | 27.934 |
| 希尔媞 | 花火、克拉莉丝 | 72.487 | 25.016 |
| 花火 | 克拉莉丝、希尔媞 | 70.576 | 28.371 |

后排由实际角色目录排除主角后真实购买；不能购买自身的规则保留。两个伤害型后排要求采样内实际正伤害，脉冲要求实际正数受影响施放及从模拟中读取存活普通敌人的减速计时，保持零伤害。两组含脉冲采样均观察到7次实际控制施放。各组后排配置不同，这些数据用于验证各配置达到门槛，不作为主角性能排名。

Windows ZIP包含10个文件，CRC、解压文件字节、更新后的原作素材声明及上一轮备份哈希均核验通过。固定夹具不代表自然通关、数值平衡或硬件手柄／音频验收；新三图未进行同规模持续压力采样。仍有501个角色版本、410件装备、1054条技能变体及1419份布局尚无接入声明，现有声明也保留逐项原作差异，全目录目标尚未完成。机器记录见[本轮验收](../reports/world-flipper-actions/validation.json)。

新工具和生成JSON固定UTF-8 LF，避免Windows的CRLF在Git规范化后令审计报告摘要失配。动作与角色动画的`--check`只检查确定性字节和原始来源，不写注册表或报告。完整游戏回归后仅统一了运行时文本换行，另复核技能、地形和诊断隔离四套件；原工作区155项Python测试全通过。从Git索引导出的独立副本同样通过155项测试，其中3项依赖忽略的本地原始缓存，按约定跳过；原始动作和1122份GIF已在主工作区另外完成全量离线复核。
