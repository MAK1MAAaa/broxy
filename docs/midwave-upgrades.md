# 波内强化与玩家前景

经验达到门槛时暂停当前战斗，展示已有三选一强化；选完所有待选项后继续同一个实例，保留位置、敌人、弹体、冷却和剩余时间。强化数值、掉落价值、商店价格、敌人配置和成功波次回收魂屑的规则不变。

此前强化只在波末生效，而成功波次会自动回收剩余魂屑；拾取范围主要改变领取时间，不能提前取得强化。现在更早拾取能够更早获得伤害、攻速、护甲或生命强化，引魂烛的拾取范围与移速取舍因此能影响当前战斗，不代表它在所有构筑中更强。

## 暂停与结算

- 升级暂停与Esc手动暂停分开维护。升级期间计时、返航弹体、敌人和反馈寿命冻结；Esc与设置可用，关闭手动暂停后仍需完成强化。
- 一次拾取获得多级时连续选择；旧按钮、重复输入与上一页完成回调不能消耗下一次选择。
- 最后选择后若同帧手动暂停或失焦，恢复HUD时保留暂停。不会生成商店、恢复满生命或重置战斗。
- 升级与终局同一步出现时先处理胜负。未处理强化仍由普通波末兜底，失败和最终胜利沿用结果流程。
- 返回标题、重开与下一波使旧升级请求、旧模拟的波末回调失效。压力基准不弹强化，个人档案隔离保持。

升级页明确显示“战斗已暂停，选完强化继续当前波次”，保留当前→强化后属性。生命灌注额外显示当前生命、选择后生命及实际回复量，仍是原有上限+12、回复12规则。

## 玩家前景

运行时版本为`foreground-player-v1`。脚下光晕和符印保留原位置；友方爆环、命中刻痕、符文线和输出浮字之后绘制角色与环绕装备，再绘制承伤数字及方向提示，最后绘制敌方预警与敌弹。没有新增素材、几何或视觉对象，数字池仍48对象，普通命中和符文反馈各32对象。

固定第六波合法四法器/四符文构筑通过正式购买、发射和16步模拟生成近身爆破与承伤。四组前后图的模拟、反馈与两套RNG哈希一致，战斗像素变化只在角色/环绕装备包络内。改善较克制，无敌闪烁最低透明度仍为0.25；关闭闪光时角色保持不透明，承伤数字保留。敌方危险信息继续覆盖角色。

## 验证

完整`./tools/test.sh`通过16332条Godot断言（39套与5个额外档案入口）、27项Python测试。波内流程76、升级UI152、前景50、runner时序14条专项通过；原生另重跑前三套以及普通反馈101、通知65、敌方预警134条。

首波原生预览使用固定种子2027和正式机器人路径，无额外金币、经验或sandbox：2178步、36.3秒实际拾取达到2级并暂停，选择护甲后在同一实例恢复到36.35秒、等级2、42魂屑，没有进入商店。种子2030覆盖自然生命强化选项。第六波视觉夹具有1200魂屑购买预算、六个选定普通敌人；危险图额外放置预警及真实敌弹对象，不是自然关卡或Boss攻击。

最初承伤夹具在16步截图时方向反馈已过期；将正式接触事件推迟到第8步并增加存活断言后重跑，避免用静帧误证方向显示。原始日志、JSONL和PNG留在本地`reports/midwave/`。

这些检查不替代[真人试玩](playtest.md)。动态辨识率、升级打断频率、选择耗时及再次开局意愿仍待记录。

## 复现

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tools/preview_combat_upgrades.gd '--' --case=choice --capture=reports/midwave/upgrade-choice.png
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tools/preview_player_foreground.gd '--' --variant=after --case=blast --capture=reports/midwave/foreground-blast-after.png
```

前景`before`模式只加载本地`.tools/world-before-foreground.gd`快照，由本轮前的World源码去掉`class_name`保存，不随正式包分发。缺失时退出2，不以当前版本冒充基线。

## 对局、性能与分发

核心`prototype-0.1.0+2161ed68c2ae`、policy`orbit-avoid-v1/shop-v1/upgrade-timing-v2+f9be8607dd88`的新30局为28胜2败，战斗中强化258次、波末129次。runner现在在存活战斗步后执行原升级偏好，终局保留兜底；走位、购物和升级评分未变。Main编排纳入核心指纹，升级时机改变RNG消耗与后续报价，因此不与旧26胜4败声明轨迹等价，不以样本差额确定真人难度或引魂烛收益。详见[模拟报告](../reports/midwave/simulation.json)。

本轮固定seed1792123517、正常Main八法器5秒预热+60秒原生检查通过：7069帧、117.789FPS/P99 17.757ms，末尾300/600/200，八法器均有真实伤害。基准没有打开升级页，默认设置、无个人档案，未与其他Godot任务并行。它是短时流程/性能检查，不是新的300秒验收；上一轮300秒118.282FPS保留不改。见[本轮60秒](../reports/midwave/performance-60s.json)及[源码与旧报告审计](../reports/midwave/performance-check.json)。

Windows包重新导出、x86_64/ZIP CRC/成员字节校验、原生EXE启动截图通过，ZIP SHA-256为`1fc6c2175186d5d280ba7a8bcb0dda2a252aa80c26f8f6067531d645e96085f8`。旧ee445dc包保留且哈希匹配原验收。macOS未在Windows重建，Authenticode未配置，真人试玩仍待开展。最终证据见[validation.json](../reports/midwave/validation.json)，原生夹具与图像哈希见[native-fixtures.json](../reports/midwave/native-fixtures.json)。
