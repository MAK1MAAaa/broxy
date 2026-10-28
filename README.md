# 秘术余烬 / Embers

Godot 4.7.2 普通版、带类型标注的 GDScript 开发的 macOS / Windows 单人割草原型。围绕占格背包、可升阶法器与行为符文，完成短波次战斗、经验强化、商店整理和最终 Boss。

主菜单新增四地图选择：秘仪祭坛、沉沼遗庭、苍霜圣庭、余烬荒原。三张新图具有不同地貌和减速区域，同时影响玩家与敌人，离开恢复；本局八波沿用所选地图。界面移除重复小字，战斗中取消生命条下方的通知及右下角说明；关键数值与风险保留，低频操作改为按钮提示。规则与验证见[地图与地形](docs/maps.md)。

武器、遗物和松散符文现在装入盒状背包。购买自动找空位，玩家手动移动、旋转和合成；两件同名同阶物品升一阶，最高三阶。初始6×4格，可付32、48魂屑扩到6×6；背包中的所有法器自动攻击，遗物直接生效。操作与数值见[秘术背包](docs/backpack.md)，专项预览使用 `res://tools/preview_backpack.gd`。

当前源码包含8种法器、14种遗物和 `rogue-choices-v1` 秘术抉择。第1波后可选霜火共鸣或白骨齐鸣核心；第2波后可自愿挑战追猎者，击杀后在波间自选符文。普通波可选择原途、密集魂潮或重甲巡礼；引魂烛与正上方相接法器联动，改变目标优先级。完成第3波解锁霜矛起手，击杀追猎者解锁散魂起手，没有永久属性加成。完整规则与边界见[秘术抉择](docs/rogue-choices.md)。

原46项 `engraved-07` 素材与 `arsenal-atlas-v5` 图集保持，新增3张 `biomes-01` 地图背景，加入两张技能遗物图标后共51项资源。背包沿用 `backpack-targets-v1` 合成／装符候选和逐格预览，新增淡绿↑烛引标记；追猎者有冠、圈和生命条，寒焰以蓝金双环显示，敌方危险提示继续置顶。操作与美术约定见[秘术背包](docs/backpack.md)及 `docs/art-direction.md`。

归魂环发射0.60秒后追随玩家当前位置返航，往返共享已命中目标，不会重复伤害同一敌人；本体可命中2个不同目标，成功弹射会永久取消返航。冷却独立推进，接回魂环不回复生命或魂屑。新增内容沿用商店购买、商品锁定、遗物购前对照和符文装入预览；归魂环阶段的Windows完整回归、原生画面、固定种子压力采样与新包验证记录保留。八法器头部使用预生成图集与复用缓冲，保持危险提示优先。

同时支持遗物邻接共鸣：法器与遗物共边时，每件Ⅰ／Ⅱ／Ⅲ阶遗物为该法器额外提供3%／6%／12%伤害，总共鸣上限18%；对角接触不计，同一遗物多格接边只计一次。购买、合成、旋转和出售后按真实布局重算，详情显示来源与实际伤害。盒子增加皮革底、金属角扣、阶级刻痕和对应符文徽章，共鸣接缝仅强调当前选中或合法摆放的关系。完整规则与验收见[遗物共鸣](docs/resonance.md)。

当前经验升级会暂停战斗，选完三选一后继续原位置、弹体、冷却与剩余时间；多级连续选择，Esc与设置仍可用，死亡和波末优先结算。生命强化显示实际生命补充。提前拾取可提前取得强化，让拾取范围与移速的取舍影响当前波次。角色与环绕法器现在显示在友方特效和输出数字上方，承伤提示与敌方危险信息继续置顶。规则、边界和验收见 [波内强化与玩家前景](docs/midwave-upgrades.md)。

战斗新增空格冲刺：向当前移动方向短冲0.20秒，静止时沿面向，距离约132像素，冷却2.4秒。起始0.12秒短暂闪避，可冲离减速地形；冲刺末段仍可受伤。顶栏显示冷却，冷却期间按键不缓存，按住不连发；暂停、升级和失焦会清除未消费输入。数值、残影与验证范围见[短冲技能](docs/dash.md)。

实际用冲刺保护挡住接触、敌方弹体或祭仪攻击时，玩家附近短暂显示一次“闪避”确认；原有受击无敌生效或没有实际命中时不提示。同次冲刺最多一次，不改变伤害、奖励、冷却或保护时长。关闭受击闪光仍保留文字，暂停冻结提示，敌方预警继续置顶。规则和本轮验收见[成功闪避确认](docs/dash-evasion.md)。

Q释放秘术脉冲：半径144内的普通敌人径向击退70像素，独立减速35%持续1秒，冷却8秒。首领和追猎者免疫；不造成伤害、不挡弹、不清祭仪、不打断蓄力。与冰霜取更强者但分别计时，不触发霜火；可配合空格冲刺脱离近身包围。规则、输入与诊断入口见[秘术脉冲](docs/pulse.md)。

新增两件主动技能遗物：单格折影扣缩短冲刺冷却但降低普通移速；单格回响石扩大脉冲范围但延长冷却。沿用22魂屑基础价及Ⅰ／Ⅱ／Ⅲ阶1／2／4权重，冲刺冷却最低1.2秒，脉冲半径最高216、冷却最高16秒。真实施放锁定本次参数，改装只影响下次；购前对照、合成和顶栏提示显示实际数值。规则与验收见[主动技能遗物](docs/skill-relics.md)。

战斗现在显示实际伤害与承伤浮字，并提示受击方向。普通主命中新增四类短暂刻痕，持续0.12秒；贯穿显示淡绿双轨，弹射显示真实转向的冷蓝折角，爆破显示暖金放射纹，敌方预警始终位于最上层。刻痕采用32对象固定池与最多12批次绘制，次级溅射不再叠痕；暂停时关闭闪光会立即清除，重新开启不重播。弹体圆点、弹射环和拖尾采用批量绘制。结算新增最后受击来源和各法器实际伤害贡献。购买符文后会自动选中，并把键盘焦点移到法器的“装入”按钮，便于完成改装。

冲锋蓄力显示短双轨方向箭头，施法蓄力显示闭合刻环；它们表示攻击意图，不代表完整碰撞范围或术士锁定瞄准。Boss战明确显示“击败首领”和“限时”，最后10秒使用静态暖色提醒。波末结算会清理暂停状态，避免下一波留下不可见的暂停。

商店法器卡按自动购买落点预计每枚伤害、每次枚数和标称攻击间隔，计入当前全局属性与该位置共鸣；没有完整空位时不虚构购后数值。背包详情和HUD提示显示各法器实际伤害，悬停可查看行为、共鸣来源与符文效果；数值未计符文追加命中，也不是实际DPS。刷新或改装后，旧界面按钮立即失效，避免按旧卡购买新商品。

幽焰现在能在目标恰好位于正后方时开始转向，避免原方向插值卡住或将速度归零。普通转向曲线、速度、追踪范围与寿命保持原规则，修复不保证追上已经远离的目标。

强化卡在按钮上方显示「当前 → 强化后」的实际属性，计入已获得的遗物与强化。每次展示只接受一次选择，连续输入不会跳过下一组；选择起始法器后再打开设置，也会保留窗口和来源焦点。

战斗首领血条位于顶部状态栏第二行，避开角色、呼吸倾斜和环绕法器的完整绘制范围。战斗通知保持隐藏，右下角不增加说明；商店提示沿用原布局。

商店商品直接显示魂屑不足或背包放不下，同时保留售价与占格尺寸。暂不可买的商品仍可用键盘聚焦并查看拒绝反馈；已售商品跳过Tab。整理、合成、出售、扩容或补足余额后可继续购买。空格总数足够但形状放不下时仍需整理。

商店可免费锁定最多2件未售商品，刷新及跨波后保留在原位置；锁定不保价，下一波商店按当波规则重新定价。购买后自动解锁，重开试炼清空锁定；缺钱或背包暂满仍可先锁定。卡片标题小按钮与旧金边框标出“已锁”。此前实现记录见[商店锁定](docs/shop-locks.md)，当前容量以背包规则为准。

遗物商品保留“对照”：购前查看总属性、实际补血、余额及所有法器的每枚伤害／标称间隔变化，明确显示裂砂漏的负面取舍。缺钱时标明缺额，已售商品不生成购后投影；Tab/Enter打开、Esc返回，查询不影响状态和随机数。友方尾迹保持收窄和低透明度，保留弹体头部与敌方危险层。此前设计记录见 `docs/altar-comparison.md`。

选择背包中的松散符文，可在详情中装入法器或打开“预览”，查看实际阶级、触发时机、逐弹目标上限及旧符文返袋。月镰与归魂环的爆破需要第二次直接命中；交换使用新符文空出的格子，拆卸需要真实空位。敌人受击沿用最初60毫秒短促衰减与寒霜状态色。此前实现记录见 `docs/rune-workbench.md`。

## 直接游玩

Windows x86_64入口为 `build/Embers-windows-x86_64/Embers.exe`，分发包为 `build/Embers-windows-x86_64.zip`。解压后保留同目录的 `Embers.pck` 与 `licenses/`。当前包基于最新 `main` 的四地图、秘术抉择、邻接共鸣与精简HUD，加入空格冲刺、成功闪避确认、Q脉冲、技能遗物、键位／手柄操作、设备提示及肩键翻页，并修正轻推冲刺方向，共51项资源。前一版包另存 `build/Embers-windows-before-gamepad-reading-be7d405.zip`，更早版本继续保留。Windows使用微软雅黑；本轮验收见[手柄阅读与轻推冲刺](docs/gamepad-reading.md)，macOS包保留此前版本。

最新macOS应用为 `build/Embers-minimal-hud-macos.app`，分发包为 `build/Embers-minimal-hud-macos-arm64.zip`，包含四地图选择、实际地形与精简界面，以及此前完整背包／共鸣／秘术抉择内容。适用于Apple Silicon、macOS 13及以上，使用本地ad-hoc签名。本轮界面验证见 `reports/minimal-hud-validation.json`，地图与性能历史见 `reports/terrain-validation.json`；旧包保留。

主菜单或暂停菜单的“设置 → 操作设置”可重绑四个移动主键、冲刺与脉冲；支持冲突校验、取消和恢复默认，方向键固定保留。手柄左杆／十字移动，A冲刺、X脉冲、Start暂停；菜单A确认／B返回，背包持物时X旋转、A放置、B取消，左杆或十字逐格移动。配置独立保存，诊断模式不读写个人档案。操作边界与验证见[键位与手柄](docs/controls.md)。下表为默认键盘操作。

标题、HUD和背包现在按最近有效输入切换键鼠／手柄提示；鼠标移动、释放事件和左杆漂移不会抢提示，返回键鼠后保留自定义键位。整理时显示对应A／X／B，原生拖拽仍提示松手确认；切换保留焦点、持物和冷却。规则及新验收见[输入设备提示](docs/input-prompts.md)。

手柄LB／RB可向上／下翻阅遗物对照、符文预览、秘术抉择、背包详情与结算构筑，每次约80%可视高度；只滚动当前顶层内容，保留原焦点，持物与拖拽时暂停翻页。阅读提示随设备切换。轻推左杆时的冲刺方向也已修正：死区外的有效慢移会更新面向，按A沿该方向冲刺，松杆后保留最后面向。规则和Windows验收见[手柄阅读与轻推冲刺](docs/gamepad-reading.md)。

| 操作 | 按键 |
| --- | --- |
| 移动 | WASD / 方向键 |
| 冲刺 | 空格（单次按下） |
| 秘术脉冲 | Q（单次按下） |
| 攻击与瞄准 | 自动 |
| 购买、出售、选择背包物品 | 鼠标；Tab / Enter选择按钮 |
| 整理背包 | 拖拽；或“拿起”后方向键移动、Enter放置 |
| 旋转 / 取消摆放 | R / Esc |
| 升阶 / 装符文 | 拖到同名同阶物品 / 法器，或使用详情按钮 |
| 暂停 / 继续 | Esc |
| 窗口 / 全屏 | Alt+F 或 F11 |

失去焦点自动暂停，恢复焦点后需主动继续。设置中按Esc逐层返回；暂停和设置隔离底层商店/强化的键盘焦点，关闭后恢复原控件。主菜单和暂停菜单均可调整音量、震屏与受击闪光。

## 游戏规则

- 前七波各45秒，第八波为90秒Boss战。波内达到经验门槛时暂停并选择强化，选完继续同一波；计时、弹体和冷却均冻结。波末回收剩余魂屑并在祭坛恢复生命，未处理的强化由波末兜底；死亡和最终胜利直接结算。
- 冲刺速度固定660像素/秒，不受移速加成或地形减速影响，仍受竞技场边界限制；不造成伤害。冷却从启动时开始，暂停和强化选择期间冻结，新波重置为可用。关闭受击闪光会立即清除冲刺残影，技能位移与起始保护继续生效。
- 魂屑同时增加金币和经验。每波最低收入为 `28 + 6 × (波次 - 1)`，击杀收入不足时补足；补足部分不产生经验。
- 八种法器：骨针（快速单发）、霜矛（减速）、幽焰（追踪）、散魂（扇形三发）、月镰（本体贯穿）、雷灯（窄角双发）、星陨（慢速重击）、归魂环（本体贯穿与返航）。商店均可购买，可重复存放；初始开放骨针和幽焰，完成挑战后可选择霜矛或散魂起手。
- 同类同名同阶两件可手动合成，最高三阶。法器伤害和遗物属性权重为1、2、4倍；合成不改变形状、射数或冷却，主要释放空间。两把带符文法器合成会保留目标符文，源符文退回背包；目标为空则继承源符文。
- 每个共边遗物按阶级提供3%／6%／12%局部伤害，每把法器最多18%；角接、松散符文与法器之间不产生共鸣。最终伤害为基础×法器阶级×全局倍率×（1+共鸣），共鸣不改变冷却。合成保留原全局属性，局部伤害按目标位置重新计算。
- 每件法器一个符文槽。一／二／三阶贯穿或弹射分别额外命中2／3／4个目标，弹射每跳剩余75%伤害；爆破半径68／78／88像素、溅射倍率55%／65%／75%。
- 同一弹体不重复命中同一敌人；次级溅射不再次触发符文。八种法器兼容三类符文。月镰与归魂环先本体穿过首目标，再从第二个直接命中触发符文：一阶贯穿/弹射最多命中4个不同目标，升阶后对应5／6个；爆破在第二个直接命中处触发，未命中第二目标则不爆破。
- 归魂环基础伤害16、标称间隔0.95秒、索敌范围230；速度360，发射0.60秒后以460速度追随当前玩家返航，总寿命2.40秒。往返共享命中记录；成功弹射取消返航，爆破或命中预算耗尽时消失。回收没有生命或魂屑奖励，也不重置发射冷却。上述为无加成基础值与标称间隔，不是DPS。
- 背包统一管理法器、遗物和松散符文；没有独立四法器／四备用栏位限制。所有存放法器参战，移动和旋转不改变其冷却顺序。免费换符利用新符文原格存回旧符；拆卸必须有空位。
- 出售返还累计实际买入价的50%，向下取整。不能卖掉最后一件法器，出售带符文武器需能安置退回符文。失败交易完整回滚。
- 十四种遗物按占格和阶级累加。复合遗物包括月蚀吊坠（伤害/攻速）、巡礼靴（移速/拾取）、骨盾印（护甲/生命）、裂砂漏（攻速提升但伤害下降）、血契书（一阶伤害+30%、攻速-10%，基础价22）与引魂烛（一阶拾取范围+38、移速-8，基础价18）。购买生命遗物按上限增量补血；合成与出售不免费补血。
- 每次商店4件商品；首店保证法器，第二店保证符文。刷新价格随本店刷新次数增长，下波重置。最多锁定2件未售商品，锁定与解锁免费，不增加刷新次数；刷新及跨波保留原报价位置，下一波重新定价。购买成功或重开试炼清除对应锁定，背包满不会自动解锁。
- 本地保存设置、最佳成绩和已解锁起始法器，没有永久属性成长、联网、中途续局或内购。

## 从源码运行

### Windows

需要 Windows x86_64、Python 3.10+ 和 Windows PowerShell 5.1+（或 PowerShell 7）。在仓库根目录运行：

```powershell
python tools/fetch_godot.py
python tools/fetch_windows_template.py
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --headless --editor --import --quit
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --editor
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_windows.ps1
```

下载入口使用 Python 标准库，校验官方 SHA-512，安装到被忽略的 `.tools/`，不会修改系统 Godot 安装。Windows 模板首次下载约 1.2 GiB，以校验完整官方归档；下载包和分片缓存在 `.tools/downloads/`，重跑可复用。`GODOT_BIN` 可覆盖引擎路径；`BROXY_PYTHON` 可为测试指定真实的 Python 可执行路径，Microsoft Store 占位入口不能运行测试。脚本会传播失败退出码。Git Bash 用户可继续使用 `./tools/run.sh` 和 `./tools/test.sh`。`.gitattributes` 将源码与素材保持为 LF，避免 shell 入口失效及模拟指纹因 Windows 换行转换而变化。

原生验证命令如下。性能场景会运行 5 秒预热和 300 秒采样，并打开游戏窗口；运行时保持窗口可见，避免同时运行其他图形负载：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tests/test_enemy_telegraphs.gd
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --headless --script res://tests/simulate_runs.gd '--' --seed=2026 --count=10
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 '--' --benchmark --benchmark-content --benchmark-seed=1792123517 --seconds=300
```

PowerShell 中的用户参数分隔符需写为 `'--'`，防止被 PowerShell 吞掉。性能程序默认写入 `reports/performance.json`；保留已有 macOS 记录时，先备份该文件，完成后把 Windows 结果另存，再恢复原文件。诊断参数仍不读写个人档案。Windows 普通游戏档案位于 `%APPDATA%/Godot/app_userdata/秘术余烬/`。构建尚未配置 Authenticode 签名，首次运行可能显示 Windows 的发布者提示。

### macOS

项目内已准备官方引擎和匹配模板，均放在被忽略的 `.tools/`，不修改系统应用目录。使用其他引擎路径时设置 `GODOT_BIN`。

```sh
./tools/run.sh --editor
./tools/run.sh
```

全新环境可使用 Python 3 标准库和系统 curl 下载工具；素材生成脚本需要 Python 3.10 及以上：

```sh
python3 tools/fetch_godot.py
python3 tools/fetch_macos_template.py
./tools/run.sh --headless --editor --import --quit
```

编辑器以官方 SHA-512 校验。Mac 模板从官方跨平台模板包按范围提取，并验证字节范围、外层成员 CRC 和内部全部文件 CRC。下载工具不需要 pip 或 Homebrew 依赖。

```sh
./tools/build_macos.sh
# 另存应用，避免替换正在运行的旧版：
BROXY_APP_PATH="$PWD/build/Embers-minimal-hud-macos.app" ./tools/build_macos.sh
```

构建从官方 Universal 模板提取 arm64，生成 `build/Embers.app` 并执行 ad-hoc 签名验证。引擎许可在应用的 `Contents/Resources/licenses/` 中直接可读。对外发布前应使用自己的 Developer ID 配置签名与公证。

## 验证

设备提示版Windows通过 `./tools/test.sh` 的77套Godot加5个档案入口，共29056条断言、32项Python测试；新增原生设备／UI／流程专项81／60／80条通过。修复背包事务信号后续监听收到−1的问题，验证真实放置、合成、装符及监听参数稳定。60秒原生压力完成117次提示切换、3906次小幅轴输入未抢提示，平均114.685 FPS、P99 16.998毫秒；65项源码指纹一致。六局全部结果与键位版相同；新Windows包、编译资源及系统鼠标回切通过，实体手柄范围仍未覆盖。规则与证据见[输入设备提示](docs/input-prompts.md)和 `reports/input-prompts/validation.json`。

键位／手柄版Windows通过 `./tools/test.sh` 的74套Godot加5个档案诊断入口，共28835条断言、32项Python测试；四套新增原生专项146／38／113／42条通过，包含真实GUI焦点、菜单方向导航与背包库存事务。六局自动流程除版本元数据外与技能遗物版完全一致。60秒原生压力平均113.645 FPS、P99 17.319毫秒，64项源码指纹一致；Windows已重新导出并启动EXE，另验证包内配置、改键及合成手柄路径。未连接实体手柄；系统工具对字母／功能键注入出现Pause识别差异，未据此宣称硬件键码一致性。范围与证据见[键位与手柄](docs/controls.md)和 `reports/controls/validation.json`。

技能遗物版Windows通过 `./tools/test.sh` 的70套Godot加5个档案诊断入口，共28496条断言、32项Python测试；新状态／战斗／UI专项原生262／226／53条通过，既有满背包夹具同步迁移到14遗物。两件Ⅲ阶遗物的60秒原生合成压力实际完成50次冲刺挡伤、5次Q累计受控394次，平均114.358 FPS、P99 18.387毫秒。六局既有策略对局均通关，但未购买新遗物；购买、合成、范围与冷却由专项及真实系统Q／空格另验。已重导出Windows包并启动EXE，保留前包；当前证据见[主动技能遗物](docs/skill-relics.md)和 `reports/skill-relics/validation.json`。未重复300秒、未重建Mac或开展实体手柄验收。

脉冲版Windows本轮通过 `./tools/test.sh` 的67套Godot加5个档案诊断入口，共26586条断言和32项Python测试；四套脉冲专项、原生图形、包内编译资源与系统Q输入通过。三条符文路线配对的默认／显式Q策略共6局均通关，Q策略实际施放17次、受控75次。双技能八法器合成压力预热5秒、采样60秒，实际8次Q受控287次，并完成25次冲刺挡伤，平均115.041 FPS、P99 18.375毫秒。该夹具补血、补负载及加敌弹，结果不代表真人难度；未重复300秒。规则、范围与指纹见[秘术脉冲](docs/pulse.md)和 `reports/pulse/validation.json`。此前[成功闪避确认](docs/dash-evasion.md)及[短冲技能](docs/dash.md)保持历史范围，下列旧数值保留。

地图版460ccea已通过25913条Godot断言、32项Python与18局自动构筑。解锁后补做沉沼／白骨八法器原生压力：5秒预热＋300秒，平均88.428 FPS、P99帧间隔18.597毫秒，末尾300敌人／600弹体／200掉落，达到门槛。五次CUA观察确认窗口可见，源码／素材／已交付Mac包指纹保持；初次锁屏143历史保留。仅覆盖这一压力场景，没有重跑全套、18局或打包。范围见 `reports/terrain-performance-validation.json`。

上一轮整合验证：53套Godot加5个额外档案入口，25418条断言与27项Python通过；新增状态／战斗／UI组合76／147／32条，原生组合UI32条通过。两核心各15局全部完成，192个波次实际包含共鸣法器。白骨八法器预热5秒、采样60秒平均95.754 FPS／P99 26.109ms通过；直接压力弹体默认共鸣0，真实共鸣组合另由行为专项与正常对局验证，未重复300秒。结果见 `reports/macos-main-integration-validation.json` 和 `reports/performance-rogue-bone_chorus.json`。

此前393083d版霜火核心八法器原生压力采样：5秒预热＋300秒，31652帧，平均105.504 FPS、P99 22.067毫秒，结束时300敌人／600弹体／200掉落，核心实际触发2151次，事件与命中／伤害计数包含5秒预热。使用默认设置、固定种子20261026且关闭档案读写；只覆盖该压力场景，不代表所有高阶背包构筑。结果独立保存在 `reports/performance-rogue-frostfire.json`，历史 `performance.json` 保留。

```sh
./tools/run.sh -- --benchmark --benchmark-content --benchmark-core=frostfire --benchmark-seed=20261026 --seconds=300
./tools/run.sh --headless --script res://tests/simulate_runs.gd -- --seed=2026 --count=5 --rune=all --core=bone_chorus --route=balanced --altar=accept
```

直接CLI入口`--smoke`、`--autoplay`、`--shop-preview`、`--benchmark`、`--capture-only`会在读取档案前关闭持久化；本进程的设置和成绩只留在内存，窗口标注“不保存设置与成绩”。普通启动保持原有保存行为。独立预览脚本仍各自关闭持久化。当前Embers-minimal-hud-macos.app已包含该修复；性能报告另记录实际设置、持久化状态与本次种子。

```sh
./tools/test.sh
./tools/run.sh --headless --script res://tests/test_backpack_inventory.gd
./tools/run.sh --headless --script res://tests/test_backpack_combat.gd
./tools/run.sh --headless --script res://tests/test_backpack_queries.gd
./tools/run.sh --headless --script res://tests/test_backpack_ui.gd
./tools/run.sh --headless --script res://tests/test_backpack_flow.gd
./tools/run.sh --headless --script res://tests/test_backpack_shop.gd
./tools/run.sh --headless --script res://tests/simulate_runs.gd -- --seed=2027 --require-win
./tools/run.sh -- --benchmark --benchmark-runes --seconds=300
./tools/run.sh -- --benchmark --benchmark-content --benchmark-seed=1792123517 --seconds=300
```

可用 `./tools/test.sh` 或 `tools/test.ps1` 运行Godot与Python测试。此前秘术抉择阶段Mac完整46套Godot加5个额外档案入口，23797条断言与27项Python测试通过；肉鸽状态149条、战斗122条、UI63条、真实Main／存档衔接35条。锁定起始卡跳过Tab，原ChoiceActions44条与新RogueUI63条另在原生Mac通过。两平台入口均已接入，本轮只在Mac执行。证据见 `reports/rogue-choices-validation.json`；旧套件替代关系见[测试迁移](docs/backpack-test-migration.md)，历史验收保持各轮范围。

上一轮Windows波内强化通过16332条Godot断言与27项Python测试，证据保留在 `reports/midwave/validation.json`；原生首波升级/恢复与前景对照见 `reports/midwave/native-fixtures.json`。此前归魂环、商店与符文历史验收同样保留；系统字体验证需要桌面字体访问权限。

性能测试会打开明确标记的窗口，预热5秒后采样300秒，保持300敌人、至少600投射物与200掉落，并输出 `reports/performance.json`。`--benchmark-content`使用内容目录中的法器与3类符文的真实伤害弹体，标记为`content-feedback`；`--benchmark-runes`保留原4件法器的`rune-feedback`场景；省略二者为历史`baseline`。可加 `--benchmark-seed=<正整数>` 复现生成序列；只在基准模式解析，省略时维持原随机种子，普通游戏不受影响。不同场景独立记录，不能直接推断性能差异来源。报告记录实际武器来源、默认设置、持久化状态与本次种子，内容场景另记录各法器实际伤害和末段弹体家族。测试时保持窗口可见、电脑未锁屏，避免其他图形负载；保留历史记录时先备份原性能JSON。

此前Windows背包阶段完成预热5秒加300秒原生采样：平均117.245FPS、P99 18.036ms，末尾300敌人／600弹体／200掉落，默认设置且不读写个人档案，见 `reports/backpack/performance.json`。

Windows共鸣版本另跑60秒内容场景：平均116.694FPS、P99 18.183ms，见 `reports/resonance/performance-60s.json`，没有重复300秒。该呈现压力夹具直接发射八类目录法器与一阶符文，默认局部倍率为0；共鸣伤害另由实际库存与自动发射专项验证，不将FPS泛化到所有满阶构筑。PR #4同步main时未重测图形性能，不将Windows数值作为Mac包帧率。各轮时长、源码和轨迹不同，不把差额解释为优化收益；更早记录仍保留在 `reports/midwave/`、`reports/return-ring/`。

此前内容扩充版Windows七法器300秒原生采样通过：平均60.710 FPS、P99 28.418ms，末尾300敌人／600弹体／200掉落；结果见 `reports/content/performance.json`。首次54.60 FPS的失败采样、弹体几何缓存优化与同夹具CPU微测一并保留在 `docs/content-expansion.md`，各次原生采样种子不同，不把全部帧率差额归因于单项修改。

内容扩充前的macOS源码`2a6c4b9`曾在Apple M5完成5分钟原生真实符文场景采样：27,895帧，平均92.979 FPS、P99帧间隔26.191毫秒，达到≥58 FPS / ≤33毫秒门槛，退出0。末尾300敌人/600弹体/200掉落；主/次命中473,662/1,223,944，刻痕池峰值32、容量32，结束时最近准备7个非空批次。峰值和命中累计含5秒预热，末段批次不是全程最大或GPU drawcall数。默认设置且不读写个人档案，四次CUA观察确认可见窗口和采样推进。结果见`reports/impact-performance-validation.json`；原实现验证`reports/impact-validation.json`保留当时锁屏未测的历史状态。该历史补测只记录性能，未更改源码/素材、重跑30局或重新打包，当时交付同一Embers-impact.app。旧e64bb18的90.847 FPS/P99 25.400毫秒原样另存`performance-before-impacts.json`与`benchmark-before-impacts.log`，跨种子与跨版本差额不能单独归因于刻痕。详见`docs/verification.md`。

完整模拟复用正式 `RunState` 与 `CombatSim.step`，没有额外金币、无敌或专用Boss数值。此前背包阶段核心 `prototype-0.1.0+4cafb6168fa3`、seed2026—2035×三类符文共30局为29胜1败，记录229次显式合成、60次扩容、305次战斗内强化和110次波末兜底。策略为 `orbit-avoid-v1/backpack-shop-v2/upgrade-timing-v2+7df97f24c500`，会按空间购买、合成与更换高阶符文；它是新购物策略，不与旧模型声明轨迹等价，也不据此推断真人难度。见 `reports/backpack/simulation.json`；真人试玩、整理耗时和构筑理解仍待按 `docs/playtest.md` 记录。

此前Windows共鸣阶段的完整模拟复用正式 `RunState` 与 `CombatSim.step`，没有额外金币、无敌或专用Boss数值。当时核心 `prototype-0.1.0+19514fc02a89`、seed2026—2035×三类符文共30局为30胜0败，记录208次合成、60次扩容、308次战斗内强化；186个波次含共鸣法器。策略 `orbit-avoid-v1/backpack-shop-v2/upgrade-timing-v2+5567b9f92e50` 保留购物／升级偏好，不额外整理以优化共鸣。新伤害改变后续轨迹，不与旧版声明等价，也不据此推断真人难度。见 `reports/resonance/simulation.json`；先前29胜1败原样保留，真人试玩仍需按 `docs/playtest.md` 记录。

模拟还会记录完整商店报价、余额、候选评分及停止购买/刷新原因。`tools/analyze_shop_runs.py`可生成观测分析，并用`--baseline`严格比较旧对局字段和购物trace。商店观测阶段的30局在新增观测前后旧字段完全一致，证据见`reports/shop-analysis.json`；该结果只证明所测样本不受观测影响，不表示此前的战斗修复没有改变轨迹。

美术可用Python 3.10及以上执行 `python3 tools/generate_assets.py` 确定性重建。运行 `./tools/run.sh --script res://tools/preview_art.gd` 会创建不读写个人存档的固定陈列场景，保存 `reports/art-showcase.png` 后退出；它用于检查角色、法器与预警层级，不代表实际关卡或通关表现。普通战斗、菜单及商店截图分别为 `reports/art-after.png`、`reports/art-menu.png`、`reports/art-shop.png`。

反馈与结算布局使用 `./tools/run.sh --script res://tools/preview_feedback.gd -- --view=combat` 检查，也可选择 `shop` 或 `result`。输出为 `reports/feedback-<view>.png`。这些画面明确标注为固定验证场景，不读写个人存档，也不代表实际通关。

预警/HUD可用 `./tools/run.sh --script res://tools/preview_threats.gd` 与追加 `-- --view=boss` 检查；分别保存 `reports/threat-showcase.png` 和 `reports/boss-deadline.png`。这是42个正式固定步推进后冻结的无存档陈列，Boss剩余9秒为排版夹具，不是实际打了81秒。

背包排版可用 `./tools/run.sh --script res://tools/preview_backpack.gd -- --case=filled` 检查；支持 `empty`、`merge`、`full`，追加 `--hold` 留在交互窗口，或用 `--capture=path.png` 另存截图。旧 `preview_shop.gd --view=base|boosted|fullbag|transactions` 入口也已适配真实格子。固定夹具通过正式交易布置库存，提供独立测试预算，不读写个人存档，不代表自然对局或难度验收。

素材生成器显式写入UTF-8/LF。此前Boss金饰阶段的46项资源（36张SVG、10段WAV，24枚库存图标）连续生成两遍的48个产物/元数据哈希一致，仅Boss金色发生变化，其他45项资源逐字节保持。engraved-06阶段新增三枚图标与一张八帧512×64头部图集，该阶段原42项资源保持；`arsenal-atlas-v5`按家族在尾迹后绘制头部，白核可能更完整、更亮，抗锯齿与交叠不等同旧线段画法。原生静帧及透明中心检查见 `reports/return-ring/asset-qa.json`。

共鸣与新材质预览使用 `./tools/run.sh --script res://tools/preview_resonance.gd -- --case=linked`，支持 `unlinked`、`rotated`、`full` 以及 `--hold`、`--capture=path.png`；四夹具分别显示9%、0%、6%、18%共鸣。Windows可用 `tools/run.ps1 --script res://tools/preview_resonance.gd '--' --case=linked --hold`。它只创建界面和局内状态，不加载个人档案。

素材生成器显式写入UTF-8/LF。归魂环阶段46项资源（36张SVG、10段WAV，24枚库存图标）连续生成两遍的48个产物/元数据哈希一致，原42项资源逐字节保持；新增三枚图标与一张八帧512×64头部图集。`arsenal-atlas-v5`按家族在尾迹后绘制头部，白核可能更完整、更亮，抗锯齿与交叠不等同旧线段画法。原生静帧及透明中心检查见 `reports/return-ring/asset-qa.json`。

## 项目组织

- `data/`：36个原生 Resource 内容定义，调整数值后无需改界面。
- `scripts/core/`：局内状态、经济、设置与声音。
- `scripts/combat/`：固定步长模拟、池化实体、网格碰撞、绘制和自动走位策略。
- `scripts/ui/`：菜单、HUD、升级、商店和暂停覆盖层。
- `assets/`：原创矢量资源、合成音效与第三方引擎许可。资源可用 `python3 tools/generate_assets.py` 重建。
- `tests/`：行为断言、界面回归与完整整局模拟。

当前为原型：自动模拟结果不能代替真人难度、趣味性与可读性评估；五人试玩尚未开展。

符文命中陈列使用 `./tools/run.sh --script res://tools/preview_runes.gd`，输出 `reports/rune-showcase.png`。该场景通过正式发射和碰撞生成贯穿、弹射与爆破反馈，明确标记为固定验证场景。性能与完整回归证据见 `docs/verification.md`。

普通命中陈列使用 `./tools/run.sh --script res://tools/preview_impacts.gd -- --output=res://reports/impacts-after.png`，可追加`--age-shift=0.05`或`0.12`检查淡出。12只高生命幽魂通过正式碰撞产生18次主命中；年龄偏移仅推进反馈，不能代表完整自然时间线，也不替代动态战斗或真人试玩。

Windows适配、内容扩充与背包初版已合入 `main`；本轮共鸣与材质改进位于 `codex/backpack-resonance`。每轮修改验证后创建本地 commit；引擎、缓存、构建与大型原始报告由 `.gitignore` 排除，不自动推送远程。

强化排版使用 `./tools/run.sh --script res://tools/preview_upgrades.gd -- --view=base` 检查，也支持 `boosted` 与 `sequence --hold`。base种子2、boosted种子7覆盖六类强化；固定预算通过正式购买获得遗物，102魂屑结算两次升级，不读写个人档案。当前回归、原生操作与构建指纹见 `reports/choices-validation.json`。

通知避让使用 `./tools/run.sh --script res://tools/preview_notices.gd -- --view=edge` 检查，也支持 `boss`、`long`。固定场景把角色放在可达上边界，显示真实World/UI，不读写个人档案；它用于布局检查，未模拟实际通关。当前回归、前后原生截图与构建证据见 `reports/notices-validation.json`。

军械与遗物陈列使用 `./tools/run.sh --script res://tools/preview_content.gd -- --view=arsenal --capture=res://reports/content/arsenal.png`；也支持 `relics`、`shop`、`combat`，商店加 `--inspect=hourglass` 可检查裂砂漏完整详情。Windows将入口换为 `tools/run.ps1`，用户参数分隔符写成 `'--'`。陈列通过正式内容、购买、发射及碰撞接口布置固定夹具，不写个人档案，不代表实际通关。
