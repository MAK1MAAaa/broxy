# 装备台材质细化

本轮沿用 `codex/ui-refinement` 的三栏装备台，起点为 `0586766`，集中细化原生绘制材质。

- 木货架使用四块木板明暗、有限的低对比木纹、深槽与黄铜包边。
- 皮革行囊增加面色分层、侧边包带与缝线；检视纸面加入浅纸边、标题分层和极淡的底部压纹。
- 商品卡增加暖纸边、少量边缘纤维与叠纸底边；锁定卡增加双层黄铜框和铆钉，已售卡降低材质强调。
- 格盘使用暖色布面和内凹格缝，未解锁行压低明度。盒子高光收窄，右下暗面与金属扣强化体积，保留法器、遗物、符文与技能的种类底色。

绘制继续遵循左上亮、右下暗，装饰集中在边缘，图标与文字区域保持安静。没有新增说明文字、纹理、字体、着色器、外部依赖或逐帧装饰处理。

三个呈现文件为 `ShopWorkbenchArt`、`ShopPanelSkin` 和 `BackpackGrid`。格子尺寸、物品画布、阶级、技能键、符文徽标、选中与焦点位置、摆放预览及交易逻辑均沿用上一版；木纹和布面变化按索引确定，不使用游戏随机数。

## 验证

沿用正式商店与背包夹具，检查商品正常／锁定／已售／余额不足、焦点、合成、符文、技能、合法／越界摆放、完整36格与小窗口。原生及导出 PCK 复核界面、背包、装备台、共鸣、内容呈现、美术、输入提示和软件手柄专项。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tools/preview_button_polish.gd -- --view=locked --capture=res://reports/workbench-materials/locked.png
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tools/preview_backpack.gd -- --case=full --capture=res://reports/workbench-materials/full.png
```

证据见[本轮验收](../reports/workbench-materials/validation.json)。原始截图、日志和构建保留本地；本轮不重跑战斗压力、macOS 构建或实体手柄验收。

完整 `./tools/test.sh` 通过93套 Godot 测试与5个诊断入口，共32158条断言、49项 Python 测试；原生与导出 PCK 各8套专项通过。17组源码／包内画面逐像素一致，覆盖完整格盘、类别与阶级、技能键、镶符和购买状态。

Windows 已重新构建并实际启动 EXE；ZIP CRC与5个成员字节检查通过，前包保留为 `build/Embers-windows-before-workbench-materials-0586766.zip`。素材、规则数据和商店操作文件保持原字节。
