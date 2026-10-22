# 原型验收记录

验收日期：2026年10月22日。引擎为 Godot 4.7.2 普通版；当前模拟核心/资源版本为 `prototype-0.1.0+bdd5240c97ca`，包含幽焰追踪行为；当前美术为 `engraved-02`。以下分别记录自动化、原生窗口、构建与待完成检查；“持续优化游戏”仍在进行中。

## 功能与构筑

| 检查 | 已完成结果 | 证据 |
| --- | --- | --- |
| 规则测试 | 204条断言，0失败；覆盖收入、商店、装备与升级等规则 | [tests.log](../reports/tests.log) |
| 战斗测试 | 259条断言，0失败；新增符文真实事件、爆破候选顺序与最近目标网格/线性对照；覆盖12种法器/符文组合、命中预算、爆破禁止递归、施法者瞄准、幽焰追踪，以及本轮终局冻结、减速状态、扫掠命中顺序、来源与实际伤害 | [tests.log](../reports/tests.log) |
| 界面测试 | 131条断言，0失败；覆盖真实键盘焦点与装配操作、符文引导、伤害贡献/死亡来源复盘、通知安全区，以及字体排版和装饰输入穿透 | [tests.log](../reports/tests.log) |
| 完整流程测试 | 62条断言，0失败；正式首波在2701个固定步后结束，覆盖强化→商店→下一波、暂停/恢复、失败重开、跨波统计与终局结算，以及波末暂停边界 | [tests.log](../reports/tests.log) |
| 反馈测试 | 58条断言，0失败；新增符文池、真实方向、批次上限及浮字索引回收；覆盖真实伤害浮字、目标UID分离、玩家损血优先级、受击方向、固定池容量与重置 | [tests.log](../reports/tests.log) |
| 弹体绘制测试 | 77条断言，0失败；覆盖全部法器/符文视觉家族、600/1600弹体容量、圆环厚度、过滤/清理及不改模拟和RNG | [tests.log](../reports/tests.log) |
| 商店观测测试 | 384条断言，0失败；105组冻结shop-v1对照保持trace、库存、钱包和RNG一致，覆盖拒绝原因、停止条件与快照不变性 | [tests.log](../reports/tests.log) |
| 离线分析工具 | 14项Python测试通过；覆盖配对旧字段一致性、完整库存与片段区别、缺观测保持未知、坏JSON及混合版本拒绝 | [tests.log](../reports/tests.log) |
| 实际窗口首波 | 实际运行约47秒；普通45秒首波结束后进入“秘术觉醒”，进程退出码0 | [feedback-flow-native.log](../reports/feedback-flow-native.log)、[首波结束截图](../reports/feedback-first-wave-complete.png) |
| 实际窗口商店输入 | 固定商店夹具中以CUA按Return成功装配贯穿符文，仍留在商店，没有误触“开始下一波” | 负责人原生CUA操作观察；[商店过程截图](../reports/feedback-shop.png)、[原生日志](../reports/feedback-shop-native.log) |
| 同种子整局配对模拟 | 2026—2035十个种子×三种符文策略，共30局；基线与本轮均28胜2败 | [本轮摘要](../reports/simulation-30-feedback-summary.json)、[配对比较](../reports/simulation-30-feedback-comparison.json) |

七套Godot行为测试共 **1175条断言，0失败**，另有14项Python测试通过。流程测试中的Boss终局使用加速条件；商店原生操作使用固定夹具，均只验证对应流程或交互，不代表真实整局通关。

前一阶段新增暂停边界修复：`main._finish_wave`在离开战斗前统一清除SceneTree及主场景的暂停状态。用`ended`回调中的真实`push_input(Esc)`或失焦通知，人为控制“终局已确定、deferred结算尚未执行”的时序；修复前62条中6条失败，修复后全部通过，覆盖商店、升级、Boss胜利与超时失败。普通波进入下一波后实际physics计时继续推进。该回归证明状态健壮性，尚未原生复现普通OS输入会自然落入该窄窗口，不认定它是之前倒计时反馈的唯一原因。证据为`flow-pause-boundary-before.log`和`flow-pause-boundary-after.log`。

前一阶段修复三个已复现战斗问题：终局确定后仍处理二次爆破/伤害与统计、特殊移动覆盖寒霜减速、扫掠碰撞按中心投影而非实际首次入点排序。按法器统计实际扣血，过量伤害只计剩余生命；玩家承伤保留真实来源、攻击类型与最后一击，复盘展示贡献及死亡原因，重开清空。伤害反馈按来源与目标UID合并，邻近不同敌人不误合并，玩家损血浮字最后绘制；通知条移入竞技场上方安全区。

配对模拟策略固定为 `orbit-avoid-v1/shop-v1+cf468b4c5f0f`。28对保持获胜、2对保持失败；贯穿/弹射/爆破分别9/10、10/10、9/10。seed2026贯穿仍在第3波死亡且未装配目标符文，seed2032爆破仍在第4波死亡、第3店才装配一份目标符文。27/30在进入第3波前装配目标符文。30条trace均因核心正确性修复而改变，不能声称与基线轨迹等价；仅追加反馈目标UID的版本，与保留的前一批次相比除版本字段外逐字段一致。

93.33%只代表此固定机器人策略在指定样本中的结果，不能换算为真人通关率。`elapsed`只包含战斗时间，不含购物时间；trace未记录完整商店offers，未装配不等于没刷出，也不能据此确定两个失败样本的成型原因。后期余款同时受到机器人购物偏好饱和影响，不能全部归因于经济失衡。详见[优化账本](optimization-log.md)。

随后新增独立`shop_observations`，重新运行同30局：核心版本仍为`dad5c03f6439`，观测重构使策略源指纹变为`7c19c01f20e4`，购物优先级未调整。201个商店、2490条观测均有完整四件报价；严格配对后全部旧字段及旧trace相同（仅排除新增观测元数据和策略指纹），仍28胜2败。数据与可复现分析见[新30局](../reports/simulation-30-observed.jsonl)、[分析报告](../reports/shop-analysis.json)。

新证据区分了两类情况：seed2026贯穿首店曾出现18魂屑符文，策略从65魂屑先买两件24魂屑法器后剩17，才拒绝符文；次店四轮未出现目标符文。seed2032爆破的前两店全部已记录报价未出现目标符文；seed2029贯穿也在前两店未见目标符文，最终仍通关。它们不证明未成型就是死亡原因，也不支持仅据此调整正式价格或强制发放指定符文。第5—7店停止刷新有57次策略饱和、27次达到策略刷新上限，不等于无合法消费。此前缺完整报价的局限仍适用于旧报告，不能用新观测补写旧报告的原始证据。

## 本轮符文与绘制优化

当前核心`bdd5240c97ca`增加只读符文激活事件，并对爆破与最近目标使用有效网格窗口查询。爆破保留原池槽顺序，最近目标保留严格范围与同距最低槽位优先；网格无效或直接外部调用回退线性扫描。没有调整伤害、价格、敌人或购物策略。30局固定种子配对除`balance_version`外全部字段相同，包括逐波生命、完整购物trace与2490条商店观测，仍28胜2败；源文件哈希与运行标识一致，见[最终配对报告](../reports/rune-vfx-equivalence.json)。原始`simulation-30-rune-final.jsonl`保留本地，不纳入Git。

符文刻线由真实命中及剩余行为触发，贯穿/弹射/爆破分别显示双轨、局部转向和放射纹。32个装饰对象独立于玩家承伤浮字；暂停与换波会冻结或清理。友方弹体圆点和弹射环使用MultiMesh，拖尾按视觉家族批量提交，全部留在原CanvasItem的危险信息下层；最多4800个GPU实例。固定验证[原生截图](../reports/rune-showcase.png)记录5次主命中、2次范围伤害及2/1/1次符文事件，日志[退出0](../reports/rune-preview.log)。这不替代真人辨识度验证。

## 美术与本轮战斗可读性

`engraved-02`重绘了6类角色、竞技场与菜单插画、14枚图标及应用图标；新增玩家符印与柔光资源，统一细双线、角饰、商品类别与装备编号。战斗增加轻微呼吸、倾身和尘屑，保留敌方危险信息的最高绘制层级。该美术阶段没有调整玩法数值；本轮核心修复另见上文。

共35项资源（25张SVG、10段WAV）通过XML、精确尺寸、ID/引用、禁止外链及确定性校验。重复生成后SVG/WAV字节保持一致，见`reports/art-assets.json`。实际Godot原生截图包括普通战斗`reports/art-after.png`、菜单`reports/art-menu.png`、商店`reports/art-shop.png`与固定美术陈列`reports/art-showcase.png`；固定陈列只用于美术检查，不代表真实关卡或通关记录。

本轮最终[战斗反馈截图](../reports/feedback-combat.png)已重新拍摄，展示伤害浮字、玩家损血与方向反馈、危险预警及HUD安全区；图中明确标记“固定测试场景，非实际对局”。真实首波结束证据单独使用上表的原生流程截图。

本机原先将PingFang SC解析成缺少部分简体字形的PingFang HK。“敌”“杀”等字符确实产生缺字字形；现优先采用Hiragino Sans GB，回归检查实际TextServer排版的字形RID与索引，菜单和商店原生截图已确认文字完整。

## 本机性能

本轮新增`--benchmark-runes`强压力场景，保持300敌人、600颗真实伤害弹体、200掉落，同时覆盖四法器与三类符文。原有含零伤害维持弹体的`baseline`仍可独立运行，不能将两个场景当作同一负载。未优化的强场景15秒短测仅7.184 FPS、P99 151.774毫秒，退出1，保留在[失败记录](../reports/performance-rune-vfx-before-optimization.json)。

同一批短时原生隔离诊断中，完整绘制约7.266 FPS、2340次绘制调用/帧，仅跳过友方弹体绘制约87.775 FPS、590次调用/帧。所有模式的相同固定步前缀哈希一致；墙钟窗口的步数不同，不能比较伤害总量为等量负载。[诊断报告](../reports/rune-native-profile.json)及相邻`.gd.txt`保存测试脚本；该测试不是5分钟验收。实际字体布局额外CPU耗时约0.0035毫秒/步，未据此延后真实伤害文字更新。

批量弹体绘制后，15秒完整短测为93.348 FPS、P99 26.153毫秒，仍维持300/600/200且实际产生主/次伤害，见[短测](../reports/performance-rune-batched-smoke.json)。爆破与最近目标CPU微基准另见[查询报告](../reports/spatial-query-profile.json)，不能将微基准倍数换算为帧率提升。

本轮完整原生采样已通过：Apple M5、Godot 4.7.2 Compatibility、1280×720，保留VSync且`Engine.max_fps=0`。预热5秒后采样300秒，记录28,694帧；平均 **95.642 FPS**，P99帧间隔 **26.022毫秒**，满足平均≥58 FPS、P99≤33毫秒，退出码0。结束计数300敌人/600弹体/200掉落，符文刻线峰值32；全程累计主命中484,677次、范围命中1,258,294次（含预热）。CUA在开始、中段和尾段确认窗口可见、实体数量与倒计时正常；采样期间未运行其他Godot测试或构建。最终[performance.json](../reports/performance.json)与[benchmark.log](../reports/benchmark.log)对应`rune-feedback`，不混用历史baseline。

上一轮原有`baseline`的完整300秒结果为58.966 FPS、P99 30.581毫秒、17691帧，已原样保存[performance-before-rune-vfx.json](../reports/performance-before-rune-vfx.json)与[benchmark-before-rune-vfx.log](../reports/benchmark-before-rune-vfx.log)。更早反馈前为75.808 FPS/P99 29.295毫秒；锁屏中断的采样退出143，不计通过。历史样本、不同场景、不同限帧或不同代码之间不能作单因素归因。单机结果只适用于所测设备、场景和采样，不保证其他Mac或所有构筑。

## Mac应用与分发

本轮最新`build/Embers.app`已通过官方模板导出，提取Apple Silicon **arm64**切片并重新ad-hoc签名。`codesign --verify --deep --strict`、`Info.plist`检查和架构检查均通过；打包应用以`--headless --quit-after 3`启动，退出码0，最终启动日志无error。分发压缩包`build/Embers-mac-arm64.zip`完整性检查通过。证据为[build.log](../reports/build.log)、[app-boot.log](../reports/app-boot.log)与[archive-check.log](../reports/archive-check.log)。

压力测试退出后已启动最新打包应用的普通模式，CUA确认窗口标题“秘术余烬”、正常主菜单与“进入试炼”入口，未携带压力或自动走位参数；应用留在菜单供试玩。原生启动日志为`reports/app-native-title.log`。

Godot官方引擎许可和第三方声明已随包保存在`Embers.app/Contents/Resources/licenses/`，可通过Finder“显示包内容”直接读取；项目素材的原创来源及CC0授权另见`assets/PROVENANCE.md`。没有为项目自身代码指定或覆盖开源许可证。

早期`app-boot-verbose.log`、`ui-focus-smoke.log`保留了已修复的音频退出问题；部分旧模拟日志含macOS字体诊断。它们属于调试历史，最终通过状态以本记录列出的新日志为准。

## 尚未完成

- 五人真人试玩尚未开展；理解符文、波间操作耗时、再次游玩意愿与真人难度需按`docs/playtest.md`实测。
- 未在其他Apple Silicon型号或macOS13真机验收。macOS13是应用声明的最低系统版本，不是已覆盖的系统测试矩阵；本包不支持Intel Mac。
- 当前为本地ad-hoc签名，尚未使用Developer ID签名和Apple公证，未完成面向外部用户的正式发行流程。
