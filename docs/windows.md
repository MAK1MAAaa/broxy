# Windows 复现与交付

验证日期：2026年10月23日。`feature/windows` 基于已合入 macOS 工作的 `main`（`d49ef89`），复用相同玩法、数值、`engraved-04` 素材和 `primary-impact-v1` 命中反馈。

环境为 Windows 11 专业工作站版 10.0.26200 x86_64、Intel i5-13600KF、NVIDIA RTX 4070 SUPER（591.86），Godot `4.7.2.stable.official.ed1daf0bf`，OpenGL Compatibility，游戏分辨率 1280×720。

## 适配内容

- 增加原生 PowerShell 运行、测试和 Windows x86_64 导出工具；Git Bash 的既有入口也可直接识别 Windows 引擎。`GODOT_BIN` 与 `BROXY_PYTHON` 可覆盖工具路径，参数和退出码保留。
- 编辑器与模板使用 Python 标准库下载，按官方固定 SHA-512 校验完整归档，再校验提取成员 CRC 和 PE 架构；重复下载复用缓存，已在使用中的相同引擎不重复覆盖。
- 中文字体增加微软雅黑等 Windows 候选，菜单与预览共用字体配置，保留 macOS 原优先级。
- 档案隔离测试使用系统临时目录；普通启动仍用 Godot `user://profile.cfg`，诊断入口仍不读写个人档案。
- `.gitattributes` 固定文本为 LF，素材生成器显式使用 UTF-8/LF。统一换行后，模拟核心与策略指纹保持与 macOS 一致；没有调整战斗或经济逻辑。
- 商店预览可用 `--capture=path` 另存截图，避免覆盖 macOS 历史证据。

## 自动与原生验证

| 验证 | 结果 | 本地证据 |
| --- | --- | --- |
| 完整回归 | `./tools/test.sh` 与 Windows PowerShell 5.1 `tools/test.ps1` 均退出 0；2574 条 Godot 断言与 22 项 Python 测试通过 | `reports/windows/tests-bash.log`、`tests-powershell.log` |
| 系统字体与档案 | 157 条 UI 断言；普通档案 25 条、五个诊断入口各 16 条；中文目录覆盖、真实字形塑形和临时目录清理通过 | `ui-runtime.log`、`profile-*.log` |
| 原生预警读回 | 134 条断言通过，其中 12 条实际 MultiMesh 变换/颜色读回 | `enemy-telegraphs-native.log` |
| 素材重建 | 35 项素材及清单/来源共 37 个文件，两次生成一致，全部与 macOS 已提交字节一致 | [assets.json](../reports/windows/assets.json) |
| 30 局正式模拟 | seed2026—2035，三类符文各 10 局，29 胜 1 败；失败仍为 seed2026 贯穿、第3波接触攻击 | [simulation.json](../reports/windows/simulation.json)、本地 `simulation.jsonl` |
| 原生画面 | 菜单、满背包商店、强化、Boss 通知、结算、美术陈列、普通命中和符文陈列均成功截图，已核对中文与布局 | `title.png`、`shop-fullbag.png`、`upgrades-boosted.png`、`notice-boss.png`、`result.png`、`art-showcase.png`、`impact-showcase.png`、`rune-showcase.png` |
| 导出启动 | 实际 release 包运行 `--smoke`，生成 1280×720 战斗截图，退出 0 | `export-smoke.log`、`export-smoke.png` |

模拟核心为 `prototype-0.1.0+fb2ccf1ca5f1`，策略为 `orbit-avoid-v1/shop-v1+7c19c01f20e4`。本次胜负、失败样本和版本指纹符合已有 macOS 记录；历史完整 JSONL 未随仓库分发，因此没有声称两平台全部浮点数与逐帧轨迹完全相同。固定机器人结果不代表真人胜率；固定陈列也不代表实际通关。

美术陈列首次退出曾报告资源清理告警，随后 `--verbose` 复跑退出 0 且未出现告警；记录保留，未据单次告警修改玩法。

## 原生性能

运行与 macOS 相同的真实符文压力场景，保留项目 VSync 与 `Engine.max_fps=0`，预热 5 秒后采样 300 秒。共 35,389 帧，平均 **117.956 FPS**，P99 帧间隔 **18.234 毫秒**，达到平均 ≥58 FPS、P99 ≤33 毫秒门槛，退出 0。

采样结束为 300 敌人、600 弹体、200 掉落；累计主命中 472,823 次、次级命中 1,222,001 次，刻痕池峰值 32/32，最后准备 6 个非空批次。命中总数与峰值包含预热，末段批次数不是全程最大值或 GPU drawcall 数。实际设置为 volume=0.65、shake=true、flash=true，persistent_profile=false，种子 1792101457。

期间未并行运行其他 Godot 测试或构建。第120秒通过原生视口截图确认 300/600 负载和倒计时推进，同时观察到诊断窗口标题；截图也计入本次采样。这是单台设备的 process 帧间隔结果，不是 GPU 耗时；硬件和种子不同，不能把与 macOS 的差额归因于平台适配。

完整数字见 [performance.json](../reports/windows/performance.json)，测试、源码、截图与构建指纹及 ZIP CRC 核验见 [validation.json](../reports/windows/validation.json)。原始日志 `reports/windows/benchmark.log` 与性能 JSON 逐字段一致；macOS 的 `reports/performance.json` 已逐字节恢复。

## 交付

本地可执行入口为 `build/Embers-windows-x86_64/Embers.exe`，同目录保留 `Embers.pck` 与 `licenses/`；分发包为 `build/Embers-windows-x86_64.zip`。引擎、模板、导出包、截图和大型原始日志不提交源码。构建和运行命令见 [README](../README.md#windows)。

本轮只验证上述 Windows 11 设备；未进行五人真人试玩，也未配置 Authenticode 发布签名。macOS 打包依赖 macOS 系统工具，本机未重新运行 `build_macos.sh`，原有导出预设保持。
