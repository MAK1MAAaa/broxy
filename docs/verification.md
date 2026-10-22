# 原型验收记录

验收日期：2026年10月22日。引擎为 Godot 4.7.2 普通版；当前模拟核心/资源版本为 `prototype-0.1.0+143fbc0963af`，包含幽焰反向追踪修复；当前美术为 `engraved-02`。以下分别记录自动化、原生窗口、构建与待完成检查；“持续优化游戏”仍在进行中。

## 功能与构筑

| 检查 | 已完成结果 | 证据 |
| --- | --- | --- |
| 规则测试 | 204条断言，0失败；覆盖收入、商店、装备与升级等规则 | [tests.log](../reports/tests.log) |
| 战斗测试 | 302条断言，0失败；新增接触反冲朝向、四边限位与全部敌人状态回归；含符文真实事件、爆破候选顺序与最近目标网格/线性对照；覆盖12种法器/符文组合、命中预算、爆破禁止递归、施法者瞄准、幽焰追踪，以及既有终局冻结、减速状态、扫掠命中顺序、来源与实际伤害 | [tests.log](../reports/tests.log) |
| 幽焰转向边界 | 45条断言，0失败；真实四法器齐射/补刀重锁、反向与半权重退化、微小偏移方向、保速、贯穿UID排除、普通曲线与RNG；同一测试修前6失败 | [tests.log](../reports/tests.log)、[before](../reports/homing-before.log) |
| 界面测试 | 157条断言，0失败；覆盖真实键盘焦点与装配操作、符文引导、伤害贡献/死亡来源复盘、通知安全区，以及字体排版和装饰输入穿透 | [tests.log](../reports/tests.log) |
| 覆盖层输入测试 | 37条断言，0失败；真实Tab/Shift+Tab/Return覆盖底页隔离、返回源焦点、升级延迟刷新与界面替换 | [tests.log](../reports/tests.log) |
| 选择时序 | 44条断言，0失败；两次同帧Return仅选一次，旧强化按钮跨页/覆盖层/新局无效，标题选择不关闭设置；同一源码修前19失败 | [tests.log](../reports/tests.log)、[before](../reports/choice-actions-before.log) |
| 强化数值预览 | 350条断言，0失败；六类自然选项、合法满遗物加成、独立实际choose_upgrade结果、两页及同类重复升级、展示只读与布局；同一源码旧界面193失败 | [tests.log](../reports/tests.log)、[before](../reports/upgrade-previews-before.log) |
| 完整流程测试 | 76条断言，0失败；新增设置Esc逐层返回、暂停商店请求保护、最后强化延迟开店的暂停清理；正式首波在2701个固定步后结束，覆盖强化→商店→下一波、暂停/恢复、失败重开、跨波统计与终局结算，以及波末暂停边界 | [tests.log](../reports/tests.log) |
| 反馈测试 | 64条断言，0失败；新增符文池、真实方向、批次上限及浮字索引回收；覆盖真实伤害浮字、目标UID分离、玩家损血优先级、受击方向、固定池容量与重置 | [tests.log](../reports/tests.log) |
| 弹体绘制测试 | 77条断言，0失败；覆盖全部法器/符文视觉家族、600/1600弹体容量、圆环厚度、过滤/清理及不改模拟和RNG | [tests.log](../reports/tests.log) |
| 敌方预警测试 | 121条headless断言，0失败；另134条原生断言覆盖GPU实例读回、边界和颜色；headless明确跳过12项读回 | [tests.log](../reports/tests.log)、[native](../reports/enemy-telegraphs-native.log) |
| 商店动作时序 | 106条断言，0失败；刷新旧报价、同帧重复出售/选错UID、覆盖层、切波和重开旧控件均受保护；相同测试修前19失败 | [tests.log](../reports/tests.log)、[before](../reports/shop-actions-before.log) |
| 商店信息与焦点 | 51条断言，0失败；卸符拒绝/成功焦点、装配语义、商品数值与所有装备说明；数值对照正式CombatSim发射结果 | [tests.log](../reports/tests.log)、[before](../reports/shop-details-before.log) |
| 档案入口隔离 | 六入口105条断言通过；实际Main与临时ConfigFile验证正常加载保存、五诊断不读取/改写、预设persistent=false兼容与标题提示 | [profile-modes-validation.json](../reports/profile-modes-validation.json) |
| 商店观测测试 | 384条断言，0失败；105组冻结shop-v1对照保持trace、库存、钱包和RNG一致，覆盖拒绝原因、停止条件与快照不变性 | [tests.log](../reports/tests.log) |
| 离线分析工具 | 14项Python测试通过；覆盖配对旧字段一致性、完整库存与片段区别、缺观测保持未知、坏JSON及混合版本拒绝 | [tests.log](../reports/tests.log) |
| 实际窗口首波 | 实际运行约47秒；普通45秒首波结束后进入“秘术觉醒”，进程退出码0 | [feedback-flow-native.log](../reports/feedback-flow-native.log)、[首波结束截图](../reports/feedback-first-wave-complete.png) |
| 实际窗口商店输入 | 固定商店夹具中以CUA按Return成功装配贯穿符文，仍留在商店，没有误触“开始下一波” | 负责人原生CUA操作观察；[商店过程截图](../reports/feedback-shop.png)、[原生日志](../reports/feedback-shop-native.log) |
| 同种子整局配对模拟 | 2026—2035十个种子×三种符文策略，共30局；e64bb18批次29胜1败，与其上轮4f相比27局除版本外全部字段相同，3局轨迹/统计变化，无胜负转换；策略未改 | [当前配对报告](../reports/homing-simulation.json)、[历史预警等价](../reports/telegraph-equivalence.json) |

十五套Godot行为测试共 **2123条headless断言，0失败**，另有14项Python测试通过。流程测试中的Boss终局使用加速条件；商店原生操作使用固定夹具，均只验证对应流程或交互，不代表真实整局通关。

前一阶段新增暂停边界修复：`main._finish_wave`在离开战斗前统一清除SceneTree及主场景的暂停状态。用`ended`回调中的真实`push_input(Esc)`或失焦通知，人为控制“终局已确定、deferred结算尚未执行”的时序；修复前62条中6条失败，修复后全部通过，覆盖商店、升级、Boss胜利与超时失败。普通波进入下一波后实际physics计时继续推进。该回归证明状态健壮性，尚未原生复现普通OS输入会自然落入该窄窗口，不认定它是之前倒计时反馈的唯一原因。证据为`flow-pause-boundary-before.log`和`flow-pause-boundary-after.log`。

前一阶段修复三个已复现战斗问题：终局确定后仍处理二次爆破/伤害与统计、特殊移动覆盖寒霜减速、扫掠碰撞按中心投影而非实际首次入点排序。按法器统计实际扣血，过量伤害只计剩余生命；玩家承伤保留真实来源、攻击类型与最后一击，复盘展示贡献及死亡原因，重开清空。伤害反馈按来源与目标UID合并，邻近不同敌人不误合并，玩家损血浮字最后绘制；通知条移入竞技场上方安全区。

配对模拟策略固定为 `orbit-avoid-v1/shop-v1+cf468b4c5f0f`。28对保持获胜、2对保持失败；贯穿/弹射/爆破分别9/10、10/10、9/10。seed2026贯穿仍在第3波死亡且未装配目标符文，seed2032爆破仍在第4波死亡、第3店才装配一份目标符文。27/30在进入第3波前装配目标符文。30条trace均因核心正确性修复而改变，不能声称与基线轨迹等价；仅追加反馈目标UID的版本，与保留的前一批次相比除版本字段外逐字段一致。

93.33%只代表此固定机器人策略在指定样本中的结果，不能换算为真人通关率。`elapsed`只包含战斗时间，不含购物时间；trace未记录完整商店offers，未装配不等于没刷出，也不能据此确定两个失败样本的成型原因。后期余款同时受到机器人购物偏好饱和影响，不能全部归因于经济失衡。详见[优化账本](optimization-log.md)。

随后新增独立`shop_observations`，重新运行同30局：核心版本仍为`dad5c03f6439`，观测重构使策略源指纹变为`7c19c01f20e4`，购物优先级未调整。201个商店、2490条观测均有完整四件报价；严格配对后全部旧字段及旧trace相同（仅排除新增观测元数据和策略指纹），仍28胜2败。数据与可复现分析见[新30局](../reports/simulation-30-observed.jsonl)、[分析报告](../reports/shop-analysis.json)。

新证据区分了两类情况：seed2026贯穿首店曾出现18魂屑符文，策略从65魂屑先买两件24魂屑法器后剩17，才拒绝符文；次店四轮未出现目标符文。seed2032爆破的前两店全部已记录报价未出现目标符文；seed2029贯穿也在前两店未见目标符文，最终仍通关。它们不证明未成型就是死亡原因，也不支持仅据此调整正式价格或强制发放指定符文。第5—7店停止刷新有57次策略饱和、27次达到策略刷新上限，不等于无合法消费。此前缺完整报价的局限仍适用于旧报告，不能用新观测补写旧报告的原始证据。

## 当前：强化信息与选择保护

强化卡以20px冷青文字显示当前属性与选择后的结果，包含已有遗物和升级。伤害/攻速显示倍率，护甲为点数，生命为上限；不是DPS或相对提升百分比。base种子2与boosted种子7的原生截图覆盖六类属性，布局完整。350条回归用独立RunState实际choose_upgrade后的stat核对数值，验证第二页同类护甲6→7→8、展示不改RNG/状态；旧界面193失败均来自缺少卡/数值及其派生检查，没有解析失败。

原强化按钮会在deferred重绘前再次消费相同ID，而该ID可能也出现在下一组。当前按钮捕获建页代次，并在待刷新、旧页、覆盖层或非强化界面时拒绝；旧开始按钮也不能再次重开已启动的战斗。标题选择改为原位更新按下状态、角色说明和颜色，不重建整页，保留设置及来源Node。44条受控输入回归由19失败转为0；同帧Return和标题Tab/Return为真实Godot InputEvent，跨页旧信号为刻意时序夹具，不声称真人OS输入已自然落入相同帧。

CUA在原生固定场景中按Return选护甲，看到待选2→1、下一组护甲1→2；两次Tab选中该护甲再Return，进入商店并显示护甲2。另在不保存档案的Main主菜单选择幽焰、打开设置、Esc返回，实际选择说明和设置按钮焦点保留。窗口均正常退出0；原生操作按正常间隔进行，同帧边界由自动化覆盖，不等同真人整局试玩。记录见[choices-native-observations.json](../reports/choices-native-observations.json)。

生产仅改GameUI，本轮未重跑30局或5分钟压力；核心仍143fbc0963af，RunState、资源、策略、Main与绘制源码未改。最近完整性能和模拟属于e64bb18，当前回归/构建证据见[choices-validation.json](../reports/choices-validation.json)。

## 上一轮：幽焰反向追踪边界

原normalized-lerp在方向恰好相反且权重小于0.5时保持原方向，权重等于0.5时归零。现仅在0<weight≤0.5、dot<0且|cross|≤0.0001的窄区间，沿实际cross符号旋转weight弧度；精确相反时固定正侧，不使用RNG。其余路径继续原normalized-lerp，速度、伤害、范围、寿命、目标筛选与资源均未改。45条同一源码回归修前6失败、修后0失败，另Combat302条通过。

真实自动齐射夹具由三颗骨针在第21帧击杀前方目标，幽焰第22帧向后方重锁并转向2.292°，保持290像素/秒；第45帧为5.429°，随后飞出420追踪范围，后方目标仍38/38生命。此修复证明不再卡死或速度清零，不保证追上后方目标。完整逐帧记录与可复现夹具见[轨迹](../reports/homing-trajectory.json)及相邻gd.txt。

同种子30局与4f阶段相比，3局gold、trace、逐波结果及shop_observations变化，其中2局kills变化，27局除balance_version外全部字段一致。胜负保持29胜1败、无转换，策略7c19不变；不能称为全样本行为等价或真人胜率改善。源码指纹及差异见[homing-simulation.json](../reports/homing-simulation.json)。

## 上一阶段：诊断入口档案隔离

此前直接CLI的五种验证入口启动均会读取个人档案，关闭均可写回；自动流程与商店预览继续结算还会把测试成绩记为个人最佳。现在于load_profile之前对五入口设置persistent=false，仅保留本进程内的设置/成绩，普通启动不反向覆盖调用者已有的false。窗口明确标注不保存设置与成绩，普通正常持久化标题保持不变。没有清理或改写任何已有个人记录，也不推断旧记录的来源。

GameStore新增可选内部构造path，默认仍为原user://profile.cfg，现有调用与格式不变。六进程使用真实Main、真实CLI参数与唯一/private/tmp文件：修前98条25失败，修后原检查全部通过，另加7条标题检查，合计105条0失败；正常模式也验证真实读回与保存设置/成绩。十二类Godot测试共1684条及14项Python通过。原生shop-preview+capture-only截图正常、退出0，viewport不包含Mac标题栏；无CUA标题可视确认，标题由真实Main属性断言覆盖。见[报告](../reports/profile-modes-validation.json)。

f12268a逻辑提交时未重新导出应用，彼时最新包仍为745a5bb的Embers-shop.app；该阶段未改战斗核心/资源/策略，也未重跑30局或5分钟压力。当前Embers-stable.app已同时纳入该隔离与上文幽焰修复。原阶段报告保留当时状态，不改写历史证据。

## 上一轮商店交易与信息

旧卡片只绑定数组index：刷新已换报价、deferred重绘未执行时，旧“幽焰24”按钮可买到新“散魂26”；同帧Return出售备用A、Tab移至旧B、Return选择时会选中已移到该index的C。当前按钮捕获建页代次，统一拒绝数据待重绘、旧页、非商店或覆盖层下的回调。新页仍按原规则接收购买、出售、装配与下波请求。106条同一时序测试由19失败转为0；包含真实Godot InputEventKey与刻意触发旧Button信号的夹具，不声称已经通过普通真人OS输入自然复现。

满备用栏卸符失败后保留原“卸符”焦点，成功才转至退回符文UID；装配提示修为“符文已装入法器”。法器商品增加14px数值行，说明每枚伤害、每次枚数和持续攻击时标称间隔；已计当前加成，未计符文追加命中，不称实际DPS。装备名称始终可查看基础行为与当前值。51条信息回归中，原51条检查曾27失败；最终夹具购买价由固定20修正为正式shop_price，未更换检查目标，数值与真实战斗弹体/冷却对照全部通过。

原生base、boosted、fullbag三张固定商店排版退出0且人工查看通过，截图为reports/shop-<view>.png。transactions无存档窗口用CUA实际Return购买霜矛24、贯穿18并装入骨针；鼠标买血棘20、Return买时砂20，余额1000→976→958→938→918，霜矛伤害11.0→12.6、间隔0.62→0.55，与1.15伤害/1.12攻速相符（伤害显示1位小数，间隔2位小数）。详情tooltip的数据挂载由自动化验证，本轮没有独立的原生弹出框截图，不将悬停尝试记作可视验收。观察记录见[shop-native-observations.json](../reports/shop-native-observations.json)，夹具退出0；测试预算与库存明确标为固定场景，不替代真人试玩。

生产代码只修改GameUI；RunState、CombatSim、World、主场景、资源和机器人策略均与fb22ce9一致。因此未再跑30局或5分钟压力；最近30局等价与性能报告属于下述上轮源码，本轮不据此宣称重新测量。当前构建/回归指纹见[shop-validation.json](../reports/shop-validation.json)。

## 上一轮敌方意图与Boss限时

冲锋短双轨箭头显示正式锁定方向，保留中性无方向标记；施法环读取正式剩余计时，不伪造锁定瞄准。共享静态刻环网格替代每帧重建大量线段，最多1020个caster GPU实例、24次预警输入绘制命令。环进度向下量化到16段，最多约28.125毫秒装饰滞后，不改变0.65/0.45秒蓄力或发射时机。全部绘制只读模拟和RNG；暂停冻结、停止/换波/终局清理，Feedback增加6条生命周期回归。

Boss存活时HUD明确显示“击败首领 / 限时”，真实剩余≤10秒静态暖色提醒；普通波恢复原色与文字，benchmark仍优先显示“性能测试 / 采样”。26条新增UI断言覆盖边界、恢复与测试模式优先级。固定原生预览退出0：[预警](../reports/threat-preview.log)、[首领](../reports/boss-preview.log)，对应threat-showcase.png和boss-deadline.png。三组陈列由正式step推进42步后冻结；Boss9秒为手工排版条件，不是实际打了81秒或真人通关。未读写个人存档。

仅提取相同时长常量使核心版本变为4f7be4bdb91f。固定30局除版本字段外与f29全部相同，完整trace与shop_observations均一致，29胜1败；策略7c19c01f20e4和资源数值不变。此等价结果不否定下述上一阶段反冲修复造成的24局差异。

## 上一阶段暂停输入与接触反冲

真实Tab可在旧暂停层中遍历到背后的商店，Return会发出下一波请求；升级界面延迟重建也能抢走暂停层焦点。现以[Godot Control的递归焦点行为](https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-property-focus-behavior-recursive)隔离底页，保存并恢复来源控件/商店操作ID，阻止过期延迟焦点请求。设置中Esc先返回上一层，普通暂停再Esc恢复。主场景拒绝暂停时的下一波请求，最后强化结算替换界面前同步释放树与主场景暂停。新增Flow夹具修复前76条中9失败，修复后全部通过，见[before](../reports/modal-flow-before.log)、[after](../reports/modal-flow-after.log)；这是受控输入时序，不证明此前用户倒计时问题只有这一原因。

原生固定Main场景关闭了个人存档读写，CUA验证8次Tab仍在暂停层、设置第一次Esc返回暂停且第二次回商店并恢复原buy:0焦点、开始第2波后倒计时45→37、标题设置Esc回来源按钮。场景退出0，见[日志](../reports/modal-native.log)与相邻`modal-native.gd.txt`。它使用正常关卡数值，但直接构造了商店，不代表真实第一波通关或真人试玩。

旧接触反冲复用术士退避/冲锋移动方向，会把术士推向玩家，且未限制反冲后位置。现独立从接触点计算远离玩家的方向，再限制到竞技场内；保留18像素距离、原接触判定、伤害、来源和调用顺序。302条Combat回归包含普通敌人、冲锋、术士、Boss、四边、完全重叠、无敌期与非接触移动。当时核心`f29c7008e475`同种子30局为29胜1败，较`bdd5240c97ca`的28胜2败只有seed2032爆破由败转胜；24局轨迹或统计改变，见[配对报告](../reports/modal-recoil-simulation.json)。策略与所有资源数值均未改，不能将机器人结果当作真人难度改善。

## 上一阶段：符文与绘制优化

上一阶段核心`bdd5240c97ca`增加只读符文激活事件，并对爆破与最近目标使用有效网格窗口查询。爆破保留原池槽顺序，最近目标保留严格范围与同距最低槽位优先；网格无效或直接外部调用回退线性扫描。没有调整伤害、价格、敌人或购物策略。30局固定种子配对除`balance_version`外全部字段相同，包括逐波生命、完整购物trace与2490条商店观测，仍28胜2败；源文件哈希与运行标识一致，见[最终配对报告](../reports/rune-vfx-equivalence.json)。原始`simulation-30-rune-final.jsonl`保留本地，不纳入Git。

符文刻线由真实命中及剩余行为触发，贯穿/弹射/爆破分别显示双轨、局部转向和放射纹。32个装饰对象独立于玩家承伤浮字；暂停与换波会冻结或清理。友方弹体圆点和弹射环使用MultiMesh，拖尾按视觉家族批量提交，全部留在原CanvasItem的危险信息下层；最多4800个GPU实例。固定验证[原生截图](../reports/rune-showcase.png)记录5次主命中、2次范围伤害及2/1/1次符文事件，日志[退出0](../reports/rune-preview.log)。这不替代真人辨识度验证。

## 既有美术与战斗可读性

`engraved-02`重绘了6类角色、竞技场与菜单插画、14枚图标及应用图标；新增玩家符印与柔光资源，统一细双线、角饰、商品类别与装备编号。战斗增加轻微呼吸、倾身和尘屑，保留敌方危险信息的最高绘制层级。该美术阶段没有调整玩法数值；本轮核心修复另见上文。

共35项资源（25张SVG、10段WAV）通过XML、精确尺寸、ID/引用、禁止外链及确定性校验。重复生成后SVG/WAV字节保持一致，见`reports/art-assets.json`。实际Godot原生截图包括普通战斗`reports/art-after.png`、菜单`reports/art-menu.png`、商店`reports/art-shop.png`与固定美术陈列`reports/art-showcase.png`；固定陈列只用于美术检查，不代表真实关卡或通关记录。

既有[战斗反馈截图](../reports/feedback-combat.png)已重新拍摄，展示伤害浮字、玩家损血与方向反馈、危险预警及HUD安全区；图中明确标记“固定测试场景，非实际对局”。真实首波结束证据单独使用上表的原生流程截图。

本机原先将PingFang SC解析成缺少部分简体字形的PingFang HK。“敌”“杀”等字符确实产生缺字字形；现优先采用Hiragino Sans GB，回归检查实际TextServer排版的字形RID与索引，菜单和商店原生截图已确认文字完整。

## 本机性能（最近完整采样为e64bb18，本轮未重测）

当前核心143fbc0963af在Apple M5 / Godot4.7.2 Compatibility / 1280×720原生运行，保留VSync、max_fps=0。预热5秒后正式采样300秒，27,255帧，平均**90.847 FPS**，P99**25.400毫秒**，退出0并通过≥58 FPS / ≤33毫秒门槛。终点300敌/600弹/200掉落，符文刻线峰值32，含预热累计主命中472,453、次级命中1,218,763。原始[performance.json](../reports/performance.json)、[benchmark.log](../reports/benchmark.log)与源码、构建及回归指纹汇总在[homing-validation.json](../reports/homing-validation.json)。CUA在04:53、02:44、01:20、00:17确认窗口可见、300/600和倒计时推进，标题明确不保存设置与成绩，见[观察记录](../reports/homing-native-observations.json)。采样期间没有运行其他Godot测试/构建/模拟，旧用户应用在后台暂停保留。

本次实际设置为volume=0.65、shake=true、flash=true，persistent_profile=false，run_seed=1792237134，报告新增这三类元数据。诊断隔离后采用默认设置；旧采样继承个人设置且未记录，种子也不同，不能把跨采样差额单独归因于幽焰修复。上一轮fb22ce9的95.480 FPS/P99 25.588毫秒、28,645帧另存[performance-before-homing-turn.json](../reports/performance-before-homing-turn.json)与[benchmark-before-homing-turn.log](../reports/benchmark-before-homing-turn.log)；原源码指纹见该提交的threats-validation.json。更早的performance-before-homing.json保留首次启用追踪前的70.681 FPS历史记录，没有覆盖。

该完整场景以游魂及真实四法器/三符文伤害为主，不覆盖340个同时施法预警。因此另保留相同静止340敌人配置、各2秒预热+10秒采样的[预警绘制对比](../reports/telegraph-draw-comparison.json)：全施法35.172→119.555 FPS、P99 36.850→13.429毫秒；170冲锋+170施法65.087→116.678 FPS、P99 28.755→16.927毫秒。优化前后均无physics/真实攻击/600弹体，仅用于绘制诊断；进度向下量化使临近满环少一段，最大约28.125毫秒装饰滞后。输入绘制命令不是引擎最终drawcall数，报告分别记录，不据此保证其他Mac或所有构筑性能。

上次bdd5240c97ca的完整95.642 FPS / P99 26.022毫秒原样另存[performance-before-threats.json](../reports/performance-before-threats.json)和[benchmark-before-threats.log](../reports/benchmark-before-threats.log)。以下保留该阶段优化过程；不能把跨版本墙钟差额全部归于本轮预警。

## 历史：真实符文场景与弹体批量绘制

上一阶段新增`--benchmark-runes`强压力场景，保持300敌人、600颗真实伤害弹体、200掉落，同时覆盖四法器与三类符文。原有含零伤害维持弹体的`baseline`仍可独立运行，不能将两个场景当作同一负载。未优化的强场景15秒短测仅7.184 FPS、P99 151.774毫秒，退出1，保留在[失败记录](../reports/performance-rune-vfx-before-optimization.json)。

同一批短时原生隔离诊断中，完整绘制约7.266 FPS、2340次绘制调用/帧，仅跳过友方弹体绘制约87.775 FPS、590次调用/帧。所有模式的相同固定步前缀哈希一致；墙钟窗口的步数不同，不能比较伤害总量为等量负载。[诊断报告](../reports/rune-native-profile.json)及相邻`.gd.txt`保存测试脚本；该测试不是5分钟验收。实际字体布局额外CPU耗时约0.0035毫秒/步，未据此延后真实伤害文字更新。

批量弹体绘制后，15秒完整短测为93.348 FPS、P99 26.153毫秒，仍维持300/600/200且实际产生主/次伤害，见[短测](../reports/performance-rune-batched-smoke.json)。爆破与最近目标CPU微基准另见[查询报告](../reports/spatial-query-profile.json)，不能将微基准倍数换算为帧率提升。

上一阶段核心`bdd5240c97ca`的完整原生采样已通过：Apple M5、Godot 4.7.2 Compatibility、1280×720，保留VSync且`Engine.max_fps=0`。预热5秒后采样300秒，记录28,694帧；平均 **95.642 FPS**，P99帧间隔 **26.022毫秒**，满足平均≥58 FPS、P99≤33毫秒，退出码0。结束计数300敌人/600弹体/200掉落，符文刻线峰值32；全程累计主命中484,677次、范围命中1,258,294次（含预热）。CUA在开始、中段和尾段确认窗口可见、实体数量与倒计时正常；采样期间未运行其他Godot测试或构建。该阶段[performance-before-threats.json](../reports/performance-before-threats.json)与[benchmark-before-threats.log](../reports/benchmark-before-threats.log)对应`rune-feedback`，不混用历史baseline。

上一轮原有`baseline`的完整300秒结果为58.966 FPS、P99 30.581毫秒、17691帧，已原样保存[performance-before-rune-vfx.json](../reports/performance-before-rune-vfx.json)与[benchmark-before-rune-vfx.log](../reports/benchmark-before-rune-vfx.log)。更早反馈前为75.808 FPS/P99 29.295毫秒；锁屏中断的采样退出143，不计通过。历史样本、不同场景、不同限帧或不同代码之间不能作单因素归因。单机结果只适用于所测设备、场景和采样，不保证其他Mac或所有构筑。

## Mac应用与分发

本轮另存`build/Embers-choices.app`与`build/Embers-choices-mac-arm64.zip`，arm64、ad-hoc严格签名、Info.plist、headless启动退出0、ZIP完整性通过，见build-choices.log、app-boot-choices.log与archive-choices.log。包启动使用--capture-only隔离档案，不创建截图；未另做打包应用普通菜单的原生启动。五份旧应用均保留，旧暂停对局不动。

新应用、PCK、可执行文件及ZIP的SHA-256记录在[choices-validation.json](../reports/choices-validation.json)，对应当前生产源码。上一轮Embers-stable应用与完整30局/性能证据仍见[homing-validation.json](../reports/homing-validation.json)，保留其当时的源码指纹。

上一阶段`Embers-shop.app`的原生交互来自同源码无存档商店夹具；当时构建与启动记录见[shop-validation.json](../reports/shop-validation.json)。

以下是上一阶段的打包记录：

上一阶段`build/Embers.app`已通过官方模板导出，提取Apple Silicon **arm64**切片并重新ad-hoc签名。`codesign --verify --deep --strict`、`Info.plist`检查和架构检查均通过；打包应用以`--headless --quit-after 3`启动，退出码0，最终启动日志无error。分发压缩包`build/Embers-mac-arm64.zip`完整性检查通过。证据为[build.log](../reports/build.log)、[app-boot.log](../reports/app-boot.log)与[archive-check.log](../reports/archive-check.log)。

上一阶段压力测试退出后曾启动该打包应用的普通模式，CUA确认窗口标题“秘术余烬”、正常主菜单与“进入试炼”入口，未携带压力或自动走位参数；应用留在菜单供试玩。原生启动日志为`reports/app-native-title.log`。

Godot官方引擎许可和第三方声明已随包保存在`Embers.app/Contents/Resources/licenses/`，可通过Finder“显示包内容”直接读取；项目素材的原创来源及CC0授权另见`assets/PROVENANCE.md`。没有为项目自身代码指定或覆盖开源许可证。

早期`app-boot-verbose.log`、`ui-focus-smoke.log`保留了已修复的音频退出问题；部分旧模拟日志含macOS字体诊断。它们属于调试历史，最终通过状态以本记录列出的新日志为准。

## 尚未完成

- 五人真人试玩尚未开展；理解符文、波间操作耗时、再次游玩意愿与真人难度需按`docs/playtest.md`实测。
- 未在其他Apple Silicon型号或macOS13真机验收。macOS13是应用声明的最低系统版本，不是已覆盖的系统测试矩阵；本包不支持Intel Mac。
- 当前为本地ad-hoc签名，尚未使用Developer ID签名和Apple公证，未完成面向外部用户的正式发行流程。
