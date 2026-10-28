# 短冲技能

当前背包可用折影扣缩短冲刺冷却并付出普通移速代价，最低1.2秒；基础位移和保护不变。本文下方为基础冲刺版历史验收，新构筑规则见[主动技能遗物](skill-relics.md)。

战斗中单次按下空格发动冲刺。有移动输入时沿当前方向，静止时沿玩家面向；开始后方向锁定，结束后恢复普通移动。无效面向回退为向右，方向向量先归一化，斜向不增加距离。

## 数值与战斗规则

数值由 `scripts/data/dash_rules.gd` 统一定义，由正式 `CombatSim.step` 固定步推进。

| 项目 | 当前数值 |
| --- | --- |
| 持续时间 | 0.20秒 |
| 速度 | 660逻辑像素/秒 |
| 完整距离 | 132逻辑像素，触及边界时截短 |
| 冷却 | 从启动时计算2.4秒，包含冲刺过程 |
| 起始保护计时 | 0.12秒，按固定步采样 |

起始保护拦截敌人接触、敌方弹体和祭仪爆炸的真实伤害，保护时不触发接触击退。保护少于位移时长，冲刺末段可正常受伤。它使用独立计时，不覆盖或缩短原有受击后0.7秒保护；冲刺不造成伤害、不消耗生命或魂屑，不使用随机数。

四张地图使用相同的冲刺速度和距离，不乘地形减速或遗物、强化的移速加成。可用于离开泥潭、霜砂或松灰；结束后按当前位置恢复对应地形的普通移速。位移保留玩家中心的16像素竞技场内缩边界，到边后计时仍照常结束。地图当前没有新增寻路障碍。

## 输入与暂停生命周期

`Main` 只在活动战斗画面处理空格按下事件，忽略按键重复事件及Alt、Ctrl、Meta组合键。菜单、商店、强化、暂停和设置保留原有按钮交互，不发动冲刺。

`CombatWorld.request_dash()` 接受后只排队一次，下一个物理步将输入交给 `CombatSim.step(delta, movement, dash_pressed)` 并清空队列。已有待消费输入、冲刺中、冷却中、玩家死亡、波次结束、世界停止、暂停及自动走位或压力诊断时均拒绝新请求。冷却期间按键不保留至冷却结束；需再次主动按下。

手动暂停、打开波内强化、失去窗口焦点和替换局内流程会清空未消费输入，避免恢复时突然冲刺。已启动的位移、保护、冷却和残影寿命在暂停期间全部冻结，恢复后继续原模拟。死亡、波末、停止或开始新波会清除排队与旧残影；新波冲刺重置为可用。

## HUD与反馈

顶部状态栏显示“冲刺 · 空格”、“冲刺中”或剩余冷却，并配小型进度条。悬停提示提供方向、距离、冷却与地形说明。冲刺开始立即更新HUD，其余状态沿用每0.1秒的模拟快照，不用界面自行递减。指示不占键盘焦点，不拦截移动或指针事件；诊断基准场景隐藏该指示。生命条下方通知与右下角说明保持移除。

冲刺残影复用6个固定对象，每0.03秒至多记录一张，单张寿命0.16秒，使用低透明度冷青色。残影先于当前玩家绘制；本人在冲刺时保持不透明，避免受击闪烁的透明低谷影响辨识。原有玩家前景、承伤提示和敌方危险置顶顺序保留。启动复用轻音量符文音效，不新增震屏或静态素材。

关闭“受击闪光”会立即清空残影，也关闭冲刺本人的淡色提示，真实位移和保护不受影响。重新开启不重播旧残影，仍在冲刺时可在后续物理步生成新残影。

## 验证入口

两平台的 `tools/test.sh` 和 `tools/test.ps1` 均包含下列套件：

| 套件 | 覆盖范围 |
| --- | --- |
| `dash_rules` | 固定步数值、方向、冷却、地形、边界、真实接触/弹体/祭仪伤害与原有保护 |
| `dash_world` | 队列只消费一次、输入拒绝、暂停冻结、残影池容量、设置、结算清理与原生绘制顺序 |
| `dash_flow` | 真实Main按键、跨画面和强化/暂停/设置/失焦切换、队列清理与个人档案隔离 |
| `dash_ui` | 快照状态、焦点与输入穿透、多分辨率、Boss排版和界面生命周期 |

运行全套：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test.ps1
```

macOS / Git Bash使用 `./tools/test.sh`。原生绘制检查需以下入口打开窗口，headless不能证明绘制层级与动态可读性：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tests/test_dash_world.gd
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tests/test_dash_flow.gd
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tests/test_dash_ui.gd
```

`tests/simulate_runs.gd` 的核心源码指纹已包含 `dash_rules.gd`。`BotPolicy` 保留原走位规则，完整对局模拟继续使用未传冲刺输入的双参数 `step` 调用，不自动冲刺。普通模拟可用于发现流程退化，不代表使用冲刺后的胜率或难度。

固定画面预览沿用真实Main和物理步，不保存个人档案；可选 `ready`、`dash`、`cooldown`、`danger`、`interactive`。加 `--hold` 保留窗口，其中 `interactive` 接收实际键盘输入。预览工具不包含在发行包中，发行包验收使用普通主菜单进入战斗。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tools/preview_dash.gd '--' --case=dash --arena=mire --capture=res://reports/dash/dash-mire.png
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tools/preview_dash.gd '--' --case=interactive --arena=mire --hold
build/Embers-windows-x86_64/Embers.exe -- --capture-only --arena=mire
```

发行包命令仅禁用档案持久化，不自动开始对局；从主菜单进入后可测试空格、Esc和设置，再从菜单退出。没有指定截图路径时不会自动关闭。

## 本轮Windows验收

先在远程最新主线 `b15ad72` 完成基线：56套Godot加5个档案诊断入口，25916条断言、32项Python测试通过；六套原生专项、四地图画面、960×540主菜单及真实EXE启动通过。

冲刺实现后，`./tools/test.sh` 的60套Godot加5个档案诊断入口通过，共26135条断言、32项Python测试。四套冲刺原生专项分别为82、69、20、49条；World原生额外确认真实绘制通道，危险提示最后绘制。既有地图流程、波内强化、精简HUD和敌方预警原生检查同时通过。960×540与Boss顶栏由实际窗口布局和事件测试覆盖。

六张原生固定画面经主代理及独立审查，未发现遮挡或辨识阻断；均为1280×720稀疏场景。实际Windows发行包从主菜单选择沉沼试炼，系统空格输入使角色短冲并显示冷却；暂停后空格只激活继续按钮，下一次主动按下可再次冲刺。该观察验证系统输入和发行包集成，不作为真人难度研究。

四地图、两类核心及不同路线的12局固定种子普通模拟均通关；没有使用冲刺，不能据此判断技能胜率。旧素材、数据和历史报告逐字节保留。新Windows包已导出，原生启动和菜单退出通过；macOS未在Windows重建。

`tools/benchmark_dash.gd` 单独复用真实Main与World，以固定朝向、实际请求队列反复冲刺，抑制升级弹层并在每步前补血及补足负载；它是非自然对局夹具，不改变普通压力入口拒绝技能输入的规则。默认设置、沉沼／白骨核心、八法器，5秒预热后采样60秒：6710帧，平均111.831 FPS、P99帧间隔18.300毫秒；采样内25次冲刺，含预热共28次，残影峰值6。每个物理步前不少于300敌人／600弹体／200掉落，最后一步后为300／598／200。源码在采样前、采样后与当前的60项指纹一致；原生窗口在采样中可见。只覆盖这一合成压力场景，本轮没有重复300秒采样。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tools/benchmark_dash.gd '--' --seconds=60 --output=res://reports/dash/performance-raw.json
```

压力工具使用默认音量0.65、震屏和闪光开启，不保存个人档案；采样时保持移动键松开。每步前的负载数与真实步后数量分别记录。首次尝试因说明标签主题节点读取错误而中止，已修正并重新完整采样；失败日志保留本地，不作为通过结果。精简结果见 `reports/dash/performance.json`。

数值保护沿用固定步末尾的碰撞判定，0.12秒有不足一物理帧的采样量化，不承诺子步碰撞精度。手柄独占操作、重映射与真人对冲刺时机、背包构筑及移速取舍的长期试玩仍未开展。精简证据与源码、安装包指纹见 `reports/dash/validation.json`。
