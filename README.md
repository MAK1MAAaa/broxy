# 秘术余烬 / Embers

Godot 4.7.2 普通版、带类型标注的 GDScript 开发的 macOS 单人割草原型。围绕四个法器槽与可拆换行为符文，完成短波次战斗、经验强化、商店改装和最终 Boss。

当前美术版本为 `engraved-04`：主角披风和衣摆使用更连贯的灰紫亮面与深色褶谷，在68px游戏尺寸下拉开布料层次；面具、金链与原轮廓保持。竞技场沿用上一轮低对比石材，角色和敌方预警优先；保留轻微呼吸、倾身和脚下符印。中文优先使用系统 Hiragino Sans GB，避免本机苹方字体映射造成简体缺字。美术合同与来源见 `docs/art-direction.md`。

战斗现在显示实际伤害与承伤浮字，并提示受击方向。普通主命中新增四类短暂刻痕，持续0.12秒；贯穿显示淡绿双轨，弹射显示真实转向的冷蓝折角，爆破显示暖金放射纹，敌方预警始终位于最上层。刻痕采用32对象固定池与最多12批次绘制，次级溅射不再叠痕；暂停时关闭闪光会立即清除，重新开启不重播。弹体圆点、弹射环和拖尾采用批量绘制。结算新增最后受击来源和各法器实际伤害贡献。购买符文后会自动选中，并把键盘焦点移到法器的“装入”按钮，便于完成改装。

冲锋蓄力显示短双轨方向箭头，施法蓄力显示闭合刻环；它们表示攻击意图，不代表完整碰撞范围或术士锁定瞄准。Boss战明确显示“击败首领”和“限时”，最后10秒使用静态暖色提醒。波末结算会清理暂停状态，避免下一波留下不可见的暂停。

商店法器卡显示当前每枚伤害、每次枚数和标称攻击间隔，已计局内伤害与攻速加成。悬停装备名称可查看基础行为、数值和符文效果；数值未计符文追加命中，也不是实际DPS。刷新或改装后，旧界面按钮立即失效，避免连续输入按旧卡购买新商品或错选符文。

幽焰现在能在目标恰好位于正后方时开始转向，避免原方向插值卡住或将速度归零。普通转向曲线、速度、追踪范围与寿命保持原规则，修复不保证追上已经远离的目标。

强化卡在按钮上方显示「当前 → 强化后」的实际属性，计入已获得的遗物与强化。每次展示只接受一次选择，连续输入不会跳过下一组；选择起始法器后再打开设置，也会保留窗口和来源焦点。

战斗通知与首领血条现在位于顶部状态栏第二行，避开角色、呼吸倾斜和环绕法器的完整绘制范围。通知限一行显示，超长内容省略；时长仍为2.8秒，商店提示沿用原布局。

商店商品直接显示魂屑不足、法器槽满、备用符文满或遗物满3层，同时保留售价和当前持有数量。暂不可买的商品仍可用键盘聚焦并查看拒绝反馈；已售商品跳过Tab。腾出容量或补足余额后，商品恢复正常购买提示。

## 直接游玩

本轮最新应用为 `build/Embers-impact.app`（压缩包`build/Embers-impact-mac-arm64.zip`），新增普通法器命中刻痕，包含此前的主角布料、竞技场石材、商店条件提示、HUD避让、强化预览、诊断档案隔离和幽焰追踪修复。旧`build/Embers.app`文件保留；若旧版正在运行，先结束再打开新版。选择骨针或幽焰开局。应用面向 Apple Silicon、macOS 13 及以上；已采用本地 ad-hoc 签名，尚未进行 Developer ID 公证。

| 操作 | 按键 |
| --- | --- |
| 移动 | WASD / 方向键 |
| 攻击与瞄准 | 自动 |
| 购买、出售、选择符文和法器 | 鼠标；按钮也支持键盘焦点 |
| 暂停 / 继续 | Esc |
| 窗口 / 全屏 | Alt+F 或 F11 |

失去焦点自动暂停，恢复焦点后需主动继续。设置中按Esc逐层返回；暂停和设置隔离底层商店/强化的键盘焦点，关闭后恢复原控件。主菜单和暂停菜单均可调整音量、震屏与受击闪光。

## 游戏规则

- 前七波各45秒，第八波为90秒 Boss 战。波末回收已掉落魂屑并在祭坛恢复全部生命，再完整结算已获得升级。
- 魂屑同时增加金币和经验。每波最低收入为 `28 + 6 × (波次 - 1)`，击杀收入不足时补足；补足部分不产生经验。
- 四种法器：骨针（快速单发）、霜矛（减速）、幽焰（追踪）、散魂（扇形三发）。可重复装备，同名不合成。
- 每件法器一个符文槽：贯穿额外命中2个目标；弹射额外跳转2次、每跳剩余75%伤害；爆破产生68像素半径、55%伤害的溅射。
- 同一弹体不重复命中同一敌人；次级溅射不再次触发符文。四种法器兼容所有符文。
- 商店先选择备用符文，再点击目标法器装配。换下的符文回到背包；备用最多4份，免费拆换。
- 出售返还实际购买价的50%，向下取整。不能卖掉最后一件法器；符文背包满时，出售带符文法器或卸下符文会被完整拒绝。
- 六种遗物各最多3层。每次商店4件商品；首店保证法器，第二店保证符文。刷新价格随本店刷新次数增长，下波重置。
- 本地仅保存设置和最佳成绩，没有永久属性成长、联网、中途续局或内购。

## 从源码运行

项目内已准备官方引擎和匹配模板，均放在被忽略的 `.tools/`，不修改系统应用目录。使用其他引擎路径时设置 `GODOT_BIN`。

```sh
./tools/run.sh --editor
./tools/run.sh
```

全新环境可使用 Python 3 标准库和系统 curl 下载工具：

```sh
python3 tools/fetch_godot.py
python3 tools/fetch_macos_template.py
./tools/run.sh --headless --editor --import --quit
```

编辑器以官方 SHA-512 校验。Mac 模板从官方跨平台模板包按范围提取，并验证字节范围、外层成员 CRC 和内部全部文件 CRC。下载工具不需要 pip 或 Homebrew 依赖。

```sh
./tools/build_macos.sh
# 另存应用，避免替换正在运行的旧版：
BROXY_APP_PATH="$PWD/build/Embers-impact.app" ./tools/build_macos.sh
```

构建从官方 Universal 模板提取 arm64，生成 `build/Embers.app` 并执行 ad-hoc 签名验证。引擎许可在应用的 `Contents/Resources/licenses/` 中直接可读。对外发布前应使用自己的 Developer ID 配置签名与公证。

## 验证

直接CLI入口`--smoke`、`--autoplay`、`--shop-preview`、`--benchmark`、`--capture-only`会在读取档案前关闭持久化；本进程的设置和成绩只留在内存，窗口标注“不保存设置与成绩”。普通启动保持原有保存行为。独立预览脚本仍各自关闭持久化。当前Embers-impact.app已包含该修复；性能报告另记录实际设置、持久化状态与本次种子。

```sh
./tools/run.sh --headless --script res://tests/test_rules.gd
./tools/run.sh --headless --script res://tests/test_purchase_query.gd
./tools/run.sh --headless --script res://tests/test_combat.gd
./tools/run.sh --headless --script res://tests/test_homing.gd
./tools/run.sh --headless --script res://tests/test_ui.gd
./tools/run.sh --headless --script res://tests/test_notifications.gd
./tools/run.sh --headless --script res://tests/test_modal.gd
./tools/run.sh --headless --script res://tests/test_choice_actions.gd
./tools/run.sh --headless --script res://tests/test_upgrade_previews.gd
./tools/run.sh --headless --script res://tests/test_shop_actions.gd
./tools/run.sh --headless --script res://tests/test_shop_details.gd
./tools/run.sh --headless --script res://tests/test_shop_availability.gd
./tools/run.sh --headless --script res://tests/test_profile_modes.gd
./tools/run.sh --headless --script res://tests/test_flow.gd
./tools/run.sh --headless --script res://tests/test_feedback.gd
./tools/run.sh --headless --script res://tests/test_impact_feedback.gd
./tools/run.sh --headless --script res://tests/test_projectile_painter.gd
./tools/run.sh --headless --script res://tests/test_enemy_telegraphs.gd
./tools/run.sh --headless --script res://tests/test_simulation_shop.gd
python3 -m unittest discover -s tests -p 'test_shop_analysis.py'
./tools/run.sh --headless --script res://tests/simulate_runs.gd -- --seed=2027 --require-win
./tools/run.sh -- --benchmark --benchmark-runes --seconds=300
```

也可以用 `./tools/test.sh` 一次运行十九套Godot行为测试和Python分析器测试。当前2574条Godot无界面断言及14项Python测试全部通过（ProfileModes的六种入口分进程执行）；历史原生预警套件另通过134条断言（含12项GPU读回），记录见 `reports/tests.log` 与 `reports/enemy-telegraphs-native.log`。系统字体测试需要正常 macOS 字体访问权限；文件沙箱可能阻止 SystemFont 枚举。请在常规终端运行。性能测试会打开明确标记的窗口并显示采样倒计时，保持300敌人、至少600投射物与200掉落，预热5秒后采样300秒，输出 `reports/performance.json`。`--benchmark-runes`使用四种法器与三类符文的真实伤害弹体，报告标记为`rune-feedback`；新增`impact_visual_revision`、刻痕池容量、峰值和最后准备批次数，便于核对刻痕负载。省略该参数为含零伤害维持弹体的历史`baseline`场景，两者分别记录。测试时保持该窗口可见、Mac未锁屏，避免同时运行其他图形负载。

当前源码`2a6c4b9`已在Apple M5完成5分钟原生真实符文场景采样：27,895帧，平均92.979 FPS、P99帧间隔26.191毫秒，达到≥58 FPS / ≤33毫秒门槛，退出0。末尾300敌人/600弹体/200掉落；主/次命中473,662/1,223,944，刻痕池峰值32、容量32，结束时最近准备7个非空批次。峰值和命中累计含5秒预热，末段批次不是全程最大或GPU drawcall数。默认设置且不读写个人档案，四次CUA观察确认可见窗口和采样推进。结果见`reports/impact-performance-validation.json`；原实现验证`reports/impact-validation.json`保留当时锁屏未测的历史状态。本轮只补测和记录，未更改源码/素材、重跑30局或重新打包；仍交付同一Embers-impact.app。旧e64bb18的90.847 FPS/P99 25.400毫秒原样另存`performance-before-impacts.json`与`benchmark-before-impacts.log`，跨种子与跨版本差额不能单独归因于刻痕。详见`docs/verification.md`。

完整模拟复用正式 `RunState`、`CombatSim.step` 与商店价格，没有额外金币、无敌或专用 Boss 数值。当前核心版本`fb2ccf1ca5f1`提取只读购买校验；同种子30局与幽焰修复阶段`143fbc0963af`相比，仅排除版本字段后，包括完整购物与战斗轨迹的全部字段一致，仍29胜1败。此前接触反冲修复曾改变24局、28胜变29胜；各阶段独立比较，不代表真人胜率。策略与证据见 `docs/simulation.md`、`reports/purchase-simulation.json`，试玩流程见 `docs/playtest.md`，持续工作记录见 `docs/optimization-log.md`。

模拟还会记录完整商店报价、余额、候选评分及停止购买/刷新原因。`tools/analyze_shop_runs.py`可生成观测分析，并用`--baseline`严格比较旧对局字段和购物trace。商店观测阶段的30局在新增观测前后旧字段完全一致，证据见`reports/shop-analysis.json`；该结果只证明所测样本不受观测影响，不表示此前的战斗修复没有改变轨迹。

美术可用 `python3 tools/generate_assets.py` 确定性重建。运行 `./tools/run.sh --script res://tools/preview_art.gd` 会创建不读写个人存档的固定陈列场景，保存 `reports/art-showcase.png` 后退出；它用于检查角色、法器与预警层级，不代表实际关卡或通关表现。普通战斗、菜单及商店截图分别为 `reports/art-after.png`、`reports/art-menu.png`、`reports/art-shop.png`。

反馈与结算布局使用 `./tools/run.sh --script res://tools/preview_feedback.gd -- --view=combat` 检查，也可选择 `shop` 或 `result`。输出为 `reports/feedback-<view>.png`。这些画面明确标注为固定验证场景，不读写个人存档，也不代表实际通关。

预警/HUD可用 `./tools/run.sh --script res://tools/preview_threats.gd` 与追加 `-- --view=boss` 检查；分别保存 `reports/threat-showcase.png` 和 `reports/boss-deadline.png`。这是42个正式固定步推进后冻结的无存档陈列，Boss剩余9秒为排版夹具，不是实际打了81秒。

商店数值与排版可用 `./tools/run.sh --script res://tools/preview_shop.gd -- --view=base` 检查；也支持 `boosted`、`fullbag` 和 `transactions`，追加 `--hold` 留在交互窗口。固定夹具通过正式购买接口布置库存，提供独立测试预算，不读写个人存档，不代表正式对局或难度验收。

## 项目组织

- `data/`：26个原生 Resource 内容定义，调整数值后无需改界面。
- `scripts/core/`：局内状态、经济、设置与声音。
- `scripts/combat/`：固定步长模拟、池化实体、网格碰撞、绘制和自动走位策略。
- `scripts/ui/`：菜单、HUD、升级、商店和暂停覆盖层。
- `assets/`：原创矢量资源、合成音效与第三方引擎许可。资源可用 `python3 tools/generate_assets.py` 重建。
- `tests/`：行为断言、界面回归与完整整局模拟。

当前为原型：自动模拟结果不能代替真人难度、趣味性与可读性评估；五人试玩尚未开展。

符文命中陈列使用 `./tools/run.sh --script res://tools/preview_runes.gd`，输出 `reports/rune-showcase.png`。该场景通过正式发射和碰撞生成贯穿、弹射与爆破反馈，明确标记为固定验证场景。性能与完整回归证据见 `docs/verification.md`。

普通命中陈列使用 `./tools/run.sh --script res://tools/preview_impacts.gd -- --output=res://reports/impacts-after.png`，可追加`--age-shift=0.05`或`0.12`检查淡出。12只高生命幽魂通过正式碰撞产生18次主命中；年龄偏移仅推进反馈，不能代表完整自然时间线，也不替代动态战斗或真人试玩。

本地仓库使用`main`分支，每轮修改验证后创建本地commit；引擎、缓存、构建与大型原始报告由`.gitignore`排除。

强化排版使用 `./tools/run.sh --script res://tools/preview_upgrades.gd -- --view=base` 检查，也支持 `boosted` 与 `sequence --hold`。base种子2、boosted种子7覆盖六类强化；固定预算通过正式购买获得遗物，102魂屑结算两次升级，不读写个人档案。当前回归、原生操作与构建指纹见 `reports/choices-validation.json`。

通知避让使用 `./tools/run.sh --script res://tools/preview_notices.gd -- --view=edge` 检查，也支持 `boss`、`long`。固定场景把角色放在可达上边界，显示真实World/UI，不读写个人档案；它用于布局检查，未模拟实际通关。当前回归、前后原生截图与构建证据见 `reports/notices-validation.json`。
