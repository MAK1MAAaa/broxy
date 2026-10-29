# 商店与背包界面细化

本轮位于 `codex/ui-refinement`，从 `9663b6e` 新建分支，在现有像素幻想美术上做一轮局部界面试验。

## 视觉处理

- 商品卡保留暖纸色，增加内高光、底边与轻投影；图标使用同类别淡色托底。锁定商品使用金边，已售商品降低底色强调。
- 背包主面板采用浅绿底板与小金属扣，和商品区形成分组；空格降低缝线对比，增加内凹边缘，未解锁格显示锁形。
- 已选物品使用青色实体边；当前键盘／手柄焦点使用金色四角。焦点退出由事件触发重绘，拿起后的合法／越界预览沿用正式背包逻辑。

`ShopPanelSkin` 仅作用于商品卡和背包主面板，保留原面板内容边距；装饰忽略鼠标、不能聚焦、不逐帧处理。图标托底为42像素，原34像素图标保持，增加的空间由现有容器布局分配。物品格尺寸、图标、阶级与技能键徽标位置不变。本轮没有新增说明文案、玩法、素材生成服务或运行时依赖。

## Skills 选型

参考用户提供的[游戏美术与数值设计 Skills 和 MCP 选型清单](https://chatgpt.com/space/page_0a63d456707481919fed59f9eb1e0f50)，复用本机已有的 `create-game-assets`、`game-ui-ux` 和 `godot-ui-control`，按小范围界面样本、正式引擎预览和输入回归的流程落地。

本轮通过 Codex 的 `skill-installer` 下载到用户 skills 目录：

| Skill | 来源 | 用途 |
| --- | --- | --- |
| shader-programming | [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/tree/main/skills/disciplines/shader-programming) | 后续材质、描边等着色器工作流储备，本轮使用原生绘制 |
| ai-game-art-pipeline | [ybuild-ai/ai-game-art-pipeline-skill](https://github.com/ybuild-ai/ai-game-art-pipeline-skill) | 素材复用、小样本与引擎内验收流程 |

Skills 保存在用户目录，不作为游戏依赖提交。下载后的文件指纹记录于本轮验收；后续轮次可直接加载。当前界面由 Godot Control 与 StyleBox 绘制，沿用已有像素素材。

## 验证入口

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tools/preview_button_polish.gd -- --view=bag_focus --capture=res://reports/ui-refinement/focus.png
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tools/preview_button_polish.gd -- --view=shop --small --capture=res://reports/ui-refinement/small.png
```

新增 `bag_focus`、`bag_selected`、`bag_valid`、`bag_invalid` 四种固定画面，使用正式购买、背包选择与摆放查询。预览不读写个人档案，并校验绘制期间背包、对局和随机状态不变。`--small` 使用960×540实际窗口与1280×720逻辑画布，保存的是逻辑视口图。

检查记录见[本轮验收](../reports/ui-refinement/validation.json)。原始日志、预览图和 Windows 包保留本地；macOS 构建、战斗压力与实体手柄不属于此次局部样式验收。

完整 `./tools/test.sh` 通过92套 Godot 测试和5个诊断入口，共31899条断言、49项 Python 测试；原生及导出 PCK 各5套专项覆盖界面、连续整理、软件手柄、商店锁定与内容呈现。10组源码／包内画面逐像素一致，包含锁定、已售、余额不足、已选、焦点、合法／越界摆放、填满构筑与小窗口。独立视觉复核确认焦点退出清除角标，物品与技能徽标无遮挡，无效落点不溢出网格。

Windows 已重新导出并实际启动 EXE；ZIP CRC与5个分发文件通过检查，前包保留为 `build/Embers-windows-before-ui-refinement-9663b6e.zip`。`scripts/combat`、`scripts/core`、`scripts/data` 与 `data` 相对分支起点保持原字节，本轮未重新采样战斗性能。
