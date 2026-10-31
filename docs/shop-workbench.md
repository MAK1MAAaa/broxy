# 商店与背包装备台

本轮继续在 `codex/ui-refinement` 上重设计现有商店，起点为 `5fd030a`。主菜单、战斗 HUD、交易和背包数值沿用当前版本。

## 界面结构

| 区域 | 内容与视觉 |
| --- | --- |
| 顶部状态条 | 祭坛商店、当前波次、秘术抉择、魂屑图标与余额 |
| 左侧货架 | 四张商品卡、锁定数量与刷新按钮；木质外框、暖色纸面、大物品图标 |
| 中间行囊 | 深青皮革底板、黄铜角扣、完整6×6格盘、容量与扩容；选中青边、焦点金角 |
| 右侧装备检视 | 当前物品、真实数值、共鸣摘要及移动、旋转、合成、装符、出售操作；独立滚动 |
| 底部操作条 | 当前构筑属性与开始下一波 |

商品图标从34像素提高到48像素，并以小占格图表达物品形状；阶级和售价独立显示，售价不会被受阻状态或对照按钮挤掉。常驻卡片使用类别、特性与关键数值，不再放完整行为段落；移除“购买自动找空位”等固定说明。选中符文的信息集中到检视区，避免改变整页高度。

商品与自有物品均有可聚焦的“详情”按钮。完整行为、符文规则和共鸣来源按需打开，正文为18像素，支持键盘、手柄确认／返回及 LB／RB 翻页。详情查询不购买、不改背包或随机数；打开时隔离底层输入，关闭后恢复来源焦点。商品详情通过原报价快照和商店代次校验，旧按钮无法操作刷新后的报价。

## 实现约束

`ShopWorkbenchArt` 提供深青背景、木架／皮革／纸面与图形占格，使用 Godot 原生绘制，无新增位图、字体、着色器或运行时依赖。它只绘制表面和角扣，不接受输入、不参与焦点或逐帧更新。

布局采用原有1280×720逻辑画布与 keep 比例策略，使用 Container 排列区域。格盘仍为50像素单格；始终显示全部六行，尚未扩容的行显示锁形。详情延续 `ScrollContainer.follow_focus` 和原有商店焦点标识、模态栈与交易代次。数值从正式购买预览、背包快照和规则查询取得。

本轮使用 `game-ui-ux`、`godot-ui-control` 的布局、输入与焦点流程，以及 `create-game-assets`／`ai-game-art-pipeline` 的既有素材复用和小样本引擎验收流程。此前安装的 `shader-programming` 保留供后续材质开发，本轮无需着色器。

## 预览与验证

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tools/preview_button_polish.gd -- --view=bag_merge --capture=res://reports/shop-workbench/merge.png
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tools/preview_button_polish.gd -- --view=bag_record --capture=res://reports/shop-workbench/record.png
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --headless --script res://tests/test_shop_workbench.gd
```

新增 `bag_gamepad`、`bag_merge`、`bag_rune`、`bag_record` 与 `offer_record` 画面；既有正常、余额不足、锁定、已售、焦点、选中、合法／越界摆放与小窗口预览继续使用。所有夹具不读写个人档案。

测试覆盖1280×720、960×540、1600×900三种实际窗口，保持1280×720逻辑画布；小窗口截图是逻辑视口图，不能视作物理540p截图。原始日志、截图和构建包保留本地，紧凑证据见[本轮验收](../reports/shop-workbench/validation.json)。

完整 `./tools/test.sh` 通过93套 Godot 测试与5个诊断入口，共32158条断言、49项 Python 测试。装备台新增259条布局、售价和详情交互断言；原生及导出 PCK 各9套专项覆盖商店、连续整理、软件手柄、阅读、输入提示与共鸣。

17组固定画面覆盖余额不足、锁定、已售、合成、符文、双技能、完整36格背包、两类详情和小窗口；源码与包内图逐像素一致。独立复核确认售价完整、阶级清楚、主要动作可见，越界预览仍裁剪在格盘内。Windows 重新导出并实际启动 EXE，ZIP CRC及5个成员字节通过检查；前包保留为 `build/Embers-windows-before-shop-workbench-5fd030a.zip`。

一次原生软件鼠标检查出现桌面定位偏移，保持产品与测试代码原样重跑后126条断言通过；记录不代表实体鼠标或手柄验收。战斗、核心规则、配置数据和既有素材相对起点保持原字节，本轮未重建 macOS 或重跑战斗压力采样。
