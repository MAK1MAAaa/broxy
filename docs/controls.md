# 键位设置与手柄操作

从主菜单或暂停菜单进入“设置 → 操作设置”。移动的四个主键、冲刺和脉冲均可重新绑定为单个键盘物理键；默认W／S／A／D、空格、Q。点击某个动作后按新键，冲突、保留键或修饰组合会保留原绑定并说明原因；Esc或手柄B取消本次捕获。“恢复默认”只重置这六个主键。

方向键固定作为移动备用，不能重绑。Esc、Enter、小键盘Enter、Tab、F11和修饰键保留给菜单与系统操作。重绑不会改变背包的R旋转、Enter放置和Esc取消。标题与技能提示显示当前绑定，长技能键名保持在原HUD宽度内。战斗通知与右下说明继续保持精简。

## 固定手柄映射

| 场景 | 操作 |
| --- | --- |
| 战斗移动 | 左摇杆或十字键 |
| 冲刺／脉冲 | A／X，单次按下 |
| 暂停／继续 | Start |
| 菜单选择／确认／返回 | 十字键或左杆／A／B |
| 背包选择并拿起 | 聚焦物品及“拿起 / 移动”，按A |
| 持物移动／旋转／放置／取消 | 十字键或左杆／X／A／B |

当前采用通用A／B／X文字，不自动切换主机图标，也不提供手柄按钮重绑。战斗左杆使用0.20圆形死区，保留死区之外的模拟强度，对角方向限长；键盘与十字键为全速。持物左杆采用独立的逐格操作：0.55触发一步，回到0.25以内重新待命；持续偏转不逐帧连走。方向十字键每次按下一格。

背包放置、合成和装符仍经过原库存事务；无效落点不改变物品。模态界面禁止底层背包操作，捕获按键会提前消费键鼠与手柄输入，避免穿透。普通按钮保留键盘焦点和导航，A／B显式加入项目的界面确认／取消映射，原Enter／Space／Esc等按键保留。

## 计时与存档

键盘和手柄均调用原有技能请求入口，下一物理步消费，冷却期间的输入不缓存，持续按住不连发。暂停、升级、失焦与切换界面清除未消费动作。战斗中任一设备断连会暂停并清空待执行技能，重新连接不自动继续；普通失焦暂停仍保留。

六键配置独立存放在 `profile.cfg` 的 `[controls]` 段，不混入音量、震屏和闪光设置。旧档案缺少此段时使用默认；缺键、坏类型、重复键或保留键会让整组配置回落默认，避免形成部分失效的映射。普通会话通过原GameStore保存；诊断、预览和自动流程不读写个人档案。

## 验证与复跑

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tests/test_controls_flow.gd
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tools/preview_controls.gd '--' --case=settings --capture=res://reports/controls/settings.png
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tools/preview_controls.gd '--' --case=interactive --hold
```

四套专项为 `control_bindings`、`controls_flow`、`controls_ui`、`gamepad_backpack`，使用真实InputMap、`Input.parse_input_event`、Main、GUI焦点和库存事务。涵盖档案往返及诊断隔离、旧键失效／新键生效、模拟强度、菜单方向导航、A／B分层返回、捕获与失焦、暂停、断连及背包合成／装符。预览另提供 `capture`、`conflict`、`remapped`、`gamepad` 与 `backpack`。

手柄专项注入合成按钮和轴事件，只证明软件输入路径，不代表实体手柄、驱动和蓝牙兼容性验收。原生键盘捕获、Windows发行包及源码指纹以 `reports/controls/validation.json` 为准。压力夹具继续使用固定的真实技能请求和合成负载，不将其解释为自然手柄试玩。

## 本轮Windows验收

基于 `fbb1a07`，74套Godot加5个档案诊断入口，共28835条断言、32项Python通过。新增绑定／Main流程／UI／手柄背包原生专项分别146／38／113／42条通过，旧冲刺、脉冲、档案、模态及背包专项同时通过。菜单输入探针确认本引擎默认ui_accept/ui_cancel缺手柄A/B；项目显式补齐后，真实GUI拿起、菜单十字／左杆导航、A确认与B逐层返回通过。操作页布局最初失败来自测试尚未等待旧deferred焦点，不是页面实际越界；保留原围合断言并修正测试时序后，两种窗口尺寸及完整长键名通过。

六张1280×720原生固定画面和独立复核通过；实际960×540窗口另由UI专项验证。相同种子下6局自动流程均通关，除内容及策略版本元数据外，所有游戏结果字段与上一版一致；这验证输入改造没有改变自动策略的购物、强化或战斗结果，不代表手柄真人胜率。

默认设置及两件真实合成的Ⅲ阶遗物下，八法器合成压力预热5秒、采样60秒：50次冲刺全部挡伤、5次Q受控394次，平均113.645 FPS、P99帧间隔17.319毫秒。64项源码在前、后及当前一致，采样中实际置前观察游戏；夹具补血、补负载并加入敌弹，仍不代表自然难度。移动输入或摇杆未回中会拒绝该固定方向采样。

Windows重新导出并实际启动EXE冒烟，ZIP CRC、5个成员及x64 PE通过。匹配Windows引擎另加载导出PCK与外部夹具，验证设置、E/R重绑后旧键失效、双技能、合成手柄及背包摆放。包内夹具与普通EXE启动分别记录，前包保留为 `build/Embers-windows-before-controls-fbb1a07.zip`，426项既有素材、数据和历史报告保持。

系统工具在真实操作页发送e和F6时，均被捕获为Pause并保存4194313；未记录原始事件字段，不能据此确定扫描码在哪一层发生变化，也不作为E/F6实体键验收。随后发送系统Pause，实际触发该绑定的冲刺，窗口正常关闭且无档案写入。准确E/R键码与旧键拒绝由原生解析事件及编译包夹具覆盖，未为适配工具改写物理键优先规则。

本轮没有连接实体手柄，按钮和轴验证使用引擎合成事件；未进行驱动、蓝牙或主机图标兼容性验收。未重建macOS、未重复300秒采样，也未进行长期真人手柄试玩。精简证据见 `reports/controls/validation.json`、`performance.json` 与 `simulation.json`。
