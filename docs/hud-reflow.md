# 战斗 HUD 重排

保留原作人物、武器、地图和缝合像素字体，将装备、操作与生命区分开，移除贯穿屏幕的上下纸卡栏。

| 区域 | 展示 |
| --- | --- |
| 顶部中央 | 倒计时、魂屑数量；不再显示波次、等级或冲刺 |
| 左侧 | 双列武器原图、阶级和已装符文，最多八格，超出时显示数量入口 |
| 右侧 | 两位背包后排 Q/E、主角 R、冲刺，共用半透明框；各自保留键位、图标、冷却进度和状态 |
| 底部中央 | 生命条及下方经验条，均无外围面板；生命数值、等级位于各自条内左侧 |
| 右上角 | 既有小地图，与操作框分离 |
| Boss 区域 | 仅常驻血条，一阶段玫红、二阶段金橙；无血量数字、阶段文字、招式或蓄力副条 |

两侧框使用68%不透明深蓝底，内卡叠加轻量着色，场景仍可透出。HUD 沿用1280×720参考视口与等比缩放；两侧使用边缘锚点和容器排布，底部生命区及顶部数据居中锚定。24px像素字的实际行高为32px，条高据此留足，避免等级文字越界。长键名沿用真实绑定，完整名称也可在悬停提示中查看；手柄切换不改变技能时钟和当前焦点。

Boss 名称在本波开始后的2.4秒内出现一次。当前 Boss 只在第八波 `CombatSim.begin()` 中生成，因此直接使用该波 `sim.elapsed` 作为登场时钟，随暂停冻结；读取快照、调整画面选项、重建 HUD 不会延长或重播名称。进入新的首领波次重新获得完整时段，首领死亡或战斗停止后登场时段立即清零。HUD 本身只响应事件，不轮询和推进计时。蓄力、弱点与破防仍使用既有场景内反馈；破防不会覆盖阶段血条颜色。

游戏规则、库存容量、技能槽上限、技能输入、伤害和实体更新保持。浮字安全区同步避开两侧装备框、顶部数据与小地图、底部生命条；不改变碰撞或可活动范围。

## 验证与预览

完整源码检查：`./tools/test.sh`。新增 `test_hud_reflow.gd` 验证真实控件的布局、半透明材质、条内文字、满八武器和输入穿透；`test_boss_intro.gd` 验证真实首领波次的登场、暂停、到期、界面重建、新波次与击杀清理。原键位、手柄、技能、通知及小地图检查同步更新实际布局契约。

原生固定预览（不写入玩家档案）：

```powershell
./tools/run.ps1 --script res://tools/preview_hud.gd -- --view=full --capture=res://reports/hud-reflow/preview-full.png
./tools/run.ps1 --script res://tools/preview_hud.gd -- --view=cooldown --small --gamepad --capture=res://reports/hud-reflow/preview-small-gamepad.png
./tools/run.ps1 --script res://tools/preview_hud.gd -- --view=boss-intro --capture=res://reports/hud-reflow/preview-boss-intro.png
./tools/run.ps1 --script res://tools/preview_hud.gd -- --view=boss-phase2 --capture=res://reports/hud-reflow/preview-boss-phase2.png
```

另有 `boss-settled` 和 `empty` 视图。满配夹具实际扩容并购买八件武器与两位后排；冷却通过真实动作队列触发，二阶段通过真实伤害进入。为稳定检查布局，预览给予购买预算、冻结自动攻击和敌人移动，并在首领预热时补血；这些画面不代表自然通关。绘制前后检查模拟、库存和三个随机流不变。手柄提示使用合成输入，不代表实体手柄硬件验收。

本轮完整检查通过115项套件与5项诊断，共51,537项 Godot 断言、80项 Python 素材测试；16项相关套件分别在源码原生窗口和导出 PCK 上通过。九组源码与发行包预览逐像素相同，模拟状态哈希一致；实际 EXE 冒烟检查、ZIP 文件字节及 CRC 校验通过。Windows 与 Bash 测试入口同步为同一115项套件列表。

Windows 发行包更新前备份为 `build/Embers-windows-before-hud-d08acb3.zip`，校验值与上一轮记录一致；构建产物与原始截图保留本地。验收摘要写入 `reports/hud-reflow/validation.json`。macOS 构建和运行未在 Windows 环境执行，本次 HUD 排版未重复运行压力性能基准。
