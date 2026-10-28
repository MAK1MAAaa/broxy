# 秘术脉冲

当前背包可用回响石扩大范围并延长冷却，半径最高216、冷却最高16秒；每次施放锁定真实范围与冷却。本文下方为基础脉冲版历史验收，新构筑规则见[主动技能遗物](skill-relics.md)。

战斗中单次按下Q，以当前物理步起点为中心推离近身普通敌人，并短暂降低其移速。它提供站位空间，适合与空格冲刺配合；不会挡住敌弹或祭仪，也不打断蓄力。

| 项目 | 规则 |
| --- | --- |
| 范围 | 敌人中心距施法原点不超过144逻辑像素，包含边界 |
| 击退 | 径向70像素，受竞技场边界限制 |
| 减速 | 独立1秒震慑，移速乘0.65 |
| 冷却 | 从施放开始计算8秒；空放也消耗 |
| 免疫 | 首领和追猎者不受击退或震慑 |
| 伤害与收益 | 不造成伤害，不提供无敌、治疗、魂屑或经验 |

数值在 `scripts/data/pulse_rules.gd`。重叠敌人按玩家原面向推离，缺失面向回退向右，不使用随机数。每次施放统计实际影响数量；同一敌人在不同施放中可重复计数，不是唯一敌人统计。

震慑与冰霜分别计时，实际移动取两者更强的减速，不相乘、不覆盖或延长冰霜。震慑不是冰霜状态，不触发霜火，不改变引魂烛的冰霜优先索敌。冲锋仍会继续，普通冲锋敌人的实际冲锋速度也受震慑影响；首领与追猎者保持原行为。敌弹、祭仪范围和蓄力计时均不清除、不重置。

## 输入与呈现

Q与空格均只排队到下一物理步，冷却输入丢弃，重复事件和Alt、Ctrl、Meta组合键不发动技能。同一物理步同时触发两技能时，先在步起点释放脉冲，再移动和冲刺；两者冷却独立。暂停、失焦、升级及画面切换清除未消费输入；暂停冻结冷却和反馈，新波重新可用。

顶栏增加“脉冲 · Q”和冷却进度，和冲刺并列；数值来自模拟快照，界面不自行计时。共享进度条采用连续步长，避免接近结束时被量化成满条。无新增战斗通知或右下常驻说明。

施法原点保留0.30秒的淡紫范围线，普通受控敌人使用克制状态色，已有冰霜色优先。关闭闪光立即撤掉动态内圈，静态范围和真实状态色保留至原寿命结束，重新开启不重播。范围绘在敌人和玩家之前，危险信息继续置顶；没有额外震屏。复用既有符文音源和独立 `pulse` 提示键，不增加位图或音源池。

范围是世界空间完整圆，场角施放时可能延伸到竞技场外，由视口和HUD自然遮挡；实际控制仍只作用于竞技场内有效敌人。当前稀疏场角预览可读，不代表所有密集场景的人类威胁辨认效果。

## 验证与复跑

新增 `pulse_rules`、`pulse_world`、`pulse_flow`、`pulse_ui` 四套专项，接入两平台测试入口。预览通过真实Main、正式物理步和伤害规则运行固定场景，不保存个人档案，未随发行包交付。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tests/test_pulse_flow.gd
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tools/preview_pulse.gd '--' --case=cast --capture=res://reports/pulse/cast.png
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tools/preview_pulse.gd '--' --case=interactive --hold
```

预览可选 `ready`、`cast`、`flash_off`、`immune`、`corner`、`danger`、`resumed`，以及接收系统Q输入的 `interactive --hold`。危险场景在施法前就放入敌弹与祭仪，施法后仍然存在。

默认 `BotPolicy` 与自动走位诊断不使用任何主动技能。完整对局脚本显式传 `--pulse-policy` 时，额外启用 `pulse-peel-v1`：至少3个可受控敌人在100像素内时请求Q，不自动冲刺。购物、升级和秘术抉择仍使用正式事务，轨迹及后续随机消费会变化，不能作为旧轨迹等价或真人胜率。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --headless --script res://tests/simulate_runs.gd '--' --seed=20261028 --count=1 --rune=all --arena=mire --core=bone_chorus --route=balanced --altar=accept --pulse-policy
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tools/benchmark_dash.gd '--' --seconds=60 --pulse-cycles --evasion-probes --output=res://reports/pulse/performance-raw.json
```

压力夹具补血、补足基础负载并为冲刺加入正伤害敌弹，周期性请求真实Q；位置维护会在后续步重新排布敌人。这是双技能和既有八法器反馈的合成压力场景，不是自然对局或平衡研究。

## Windows验收

基于 `a86b1dd`，`./tools/test.sh` 的67套Godot加5个档案诊断入口通过，共26586条断言、32项Python测试；四套脉冲原生专项分别110／63／18／77条通过。已有冲刺、原生预警和精简HUD同时通过。首次UI专项发现进度量化，修复共享冷却条为连续步长后精确值与易错尾段断言均通过。

七种1280×720稀疏沉沼画面经主代理和独立审查，双技能、Boss第二行、场角、闪光开关和危险层未发现阻断。场角保留完整圆的延伸限制。固定危险场景在施法前存在的敌弹和祭仪，施法后仍各保留一个。960×540实际窗口的双技能排版、焦点与输入穿透由UI专项覆盖。

相同种子20261028、沉沼／白骨核心／原途／接受追猎，三类符文路线各跑默认及 `pulse-peel-v1` 策略，共6局均通关；显式Q策略实际施放17次，累计受控75次。默认走位、购物和升级偏好保持；主动策略会改变轨迹与后续随机消费，样本不能证明平衡因果或真人胜率。

默认设置下双技能八法器压力预热5秒、采样60秒、6903帧：平均115.041 FPS、P99帧间隔18.375毫秒。采样内8次Q累计受控287次，含预热共9次／325次；同时25次冲刺均确认挡伤，脉冲槽峰值1、残影峰值6。步前基础负载至少300敌人／600弹体／200掉落，不计每次冲刺额外加入的敌弹；末步后300／597／200。61项运行源码在前、后与当前一致，采样中原生窗口可见。

Windows包重新导出并实际启动EXE冒烟；匹配的Windows引擎另加载导出PCK和外部夹具，验证包内普通敌人控制、首领与追猎免疫，并用系统Q观察3个敌人被推离、冷却开始，再从暂停菜单退出。此项与普通EXE冒烟分开记录。ZIP CRC、PE与文件指纹通过，前一版包保存为 `build/Embers-windows-before-pulse-a86b1dd.zip`，既有素材、数据和历史报告保持。

精简证据与指纹见 `reports/pulse/validation.json`，性能与对局摘要分别见 `performance.json`、`simulation.json`。此前冲刺和成功闪避的报告保留原始提交范围。本轮未在Windows重建macOS，未重跑300秒采样，未进行长期真人平衡或手柄独占试玩。
