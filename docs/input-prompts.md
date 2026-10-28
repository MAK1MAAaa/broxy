# 输入设备提示

后续加入LB／RB翻页，两个肩键也作为有效设备输入；阅读提示沿用同一观察器，见[手柄阅读与轻推冲刺](gamepad-reading.md)。下方旧验收记录保留原提交范围。

标题、战斗技能栏及背包整理提示会跟随最近一次有效输入。键鼠模式显示当前重绑后的移动、冲刺和脉冲主键，手柄模式显示左杆／十字、A、X和Start。背包手动持物时显示A放置、X旋转、B取消；鼠标原生拖拽继续提示松手确认。

| 输入 | 提示行为 |
| --- | --- |
| 键盘按下 | 切为键鼠；忽略自动重复和单独修饰键 |
| 鼠标按下或滚轮 | 切为键鼠；移动鼠标和松开按钮不切换 |
| A／B／X／Y／Start／十字键／LB／RB按下 | 切为该手柄；松开不切换 |
| 左杆跨过0.35 | 首次跨阈或反向跨阈时切为该手柄 |
| 左杆回到0.20以内 | 重新待命；持续同方向偏转不反复抢回提示 |
| 其他轴、未使用按钮或非有限值 | 不用于切换提示 |

这组阈值只决定提示来源。战斗仍采用0.20圆形死区与模拟强度；背包左杆仍为0.55触发一步、0.25回中。每个设备和轴分别锁存；键鼠输入保留尚未回中的手柄锁存，避免高位小幅抖动立即抢回。只连接设备不改变提示；当前手柄断连时回到键鼠，其他手柄的连接变化保留当前提示。此前“战斗中任一设备断连暂停、重连不自动继续”的规则保留。

键鼠和手柄保持可用，提示变化只调整已有文本和tooltip。切换不会重建页面、改焦点、清除持物、移动预览、修改库存、保存档案或推进冷却。捕获按键及暂停界面也能更新提示；输入仍由原来的GUI和战斗入口处理。背包保留真实交易错误、法器属性和烛引说明，原有战斗通知及右下说明继续保持精简。

## 背包信号修复

整合专项发现，原来的事务信号直接引用持物字段。第一个UI监听者执行放置并取消持物后，后续监听者会收到源UID为−1；物品实际位置仍正确。现在在发送放置、合成和装符信号前保存源UID、目标UID、落点和旋转值，所有监听者接收同一组参数，库存事务规则保持。

## 验证入口

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tests/test_input_prompts_flow.gd
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tools/preview_input_prompts.gd '--' --case=gamepad --capture=res://reports/input-prompts/gamepad.png
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tools/benchmark_dash.gd '--' --seconds=60 --pulse-cycles --evasion-probes --skill-relics --input-prompts --output=res://reports/input-prompts/performance-raw.json
```

预览提供 `keyboard`、`gamepad`、`keyboard_return`、`paused`、`backpack`、`drag` 和 `interactive --hold`。前几组由正式Main、输入事件、GUI焦点和库存流程构造固定场景；`drag` 通过鼠标按下与移动启动引擎原生GUI拖拽；交互场景用于观察系统鼠标点击后的提示回切，全部关闭个人档案读写。

`--input-prompts` 是显式压力选项：每半秒交替注入Y和未绑定F6来切换提示，每个物理步注入低于移动死区的左杆漂移，并记录漂移是否改变设备。技能仍由原有压力请求入口驱动；这些合成输入不发动额外技能。夹具补血、补负载并另加敌弹，不能作为自然手柄试玩或平衡结论。

软件手柄路径由合成按钮和轴事件验证，未覆盖实体设备、驱动、蓝牙或品牌图标。Windows包、画面及源码指纹以 `reports/input-prompts/validation.json` 为准；此前[键位设置与手柄](controls.md)及其系统按键注入限制保持原验收范围。

## 本轮Windows验收

基于 `07e9b53`，77套Godot加5个档案入口共29056条断言、32项Python测试通过。新增设备／提示UI／整合流程原生81／60／80条，旧控制、手柄背包、技能、候选和烛引专项同时通过。旧键盘文案场景在此前手柄操作之后先发真实键盘事件，保留原全文及围合断言；不通过set_controls偷偷重置设备来适配测试。背包真实鼠标事务及首个监听取消持物、修改几何的回归证明，后续监听的源／目标UID、落点和朝向保持稳定。

六种1280×720原生固定画面经独立审查；实际960×540窗口的HUD、首领布局、焦点及部分冷却数组由UI专项验证。静态就绪截图只用于看提示，不用来证明计时冻结。原生拖拽通过引擎GUI手势启动，切换后继续提示松手确认且库存保持。

两件真实合成的Ⅲ阶遗物与八法器压力预热5秒、采样60秒，实际117次提示切换、3906次低于移动死区的轴事件未改变设备；同时50次冲刺均挡伤，5次Q累计受控394次。平均114.685 FPS、P99帧间隔16.998毫秒，65项源码前后与当前一致，采样第5秒实际置前观察窗口。夹具含补血、补负载和额外敌弹，输入压力为合成事件，不作为真人平衡结论。

相同种子下6局自动流程均通关，包括版本元数据的全部结果字段与键位版一致。自动策略没有构造提示UI，该结果只证明模拟无回归；实际提示与GUI行为由上述原生专项和包内夹具覆盖。

Windows已重导出并实际启动EXE冒烟；匹配Windows引擎另加载导出PCK和外部夹具验证A/X、E/R回切、背包与原生拖拽。交互场景先由解析Y事件进入手柄提示，再用系统鼠标点击HUD，实际回到E/R，技能使用次数仍为0，正常关闭且无档案写入；与EXE启动分别记录。ZIP CRC、5成员及x64 PE通过，429个既有素材／数据／历史报告文件与51项资源保持，前包保存在 `build/Embers-windows-before-input-prompts-07e9b53.zip`。

本轮未连接实体手柄，未重试此前e/F6系统注入身份差异，未验证品牌图标、驱动或蓝牙；未重建macOS、未重复300秒采样、未开展长期真人手柄试玩。精简记录见 `reports/input-prompts/validation.json`、`performance.json` 及 `simulation.json`。
