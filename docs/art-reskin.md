# 当前游戏的明快像素美术换装

本轮在现有《秘术余烬》上替换显示风格。参考《弹射世界》的像素簇、鲜明角色轮廓、清爽界面和明快幻想色彩，保留本作鸟喙面具／兜帽主角、幽魂、爪兽、盾甲、骷髅杖术士、浮冠祭司，以及骨针等全部道具身份。游戏名称、内容、数值、四张地图与正式区域沿用原版。

## 美术规范

- 深蓝描边、奶油白受光、青绿与蓝紫衣料、暖金器物；角色以32像素左右的逻辑网格构造，统一左上受光和成簇阴影。
- 六角色画布、中心点和实际绘制大小保持。26枚道具图标仍为64×64；八格弹体图集仍为512×64，归魂环中心透明。
- 四地图保持1280×720、原竞技场 `Rect2(66,140,1148,450)` 与正式地形椭圆。像素柱、植物与晶石在战斗区外，内部为低对比平面纹理，不增加障碍。
- 界面换成奶油纸卡、深蓝文字和青绿按钮，背包保留装备盒、阶级、镶符及共鸣状态。原节点、布局和操作链沿用，中文字体继续抗锯齿。
- Q范围线改为适合浅地面的青蓝色，敌方范围预警使用深珊瑚进度弧；友方效果、玩家、承伤及敌方危险层顺序保持。关闭闪光、暂停和声音规则沿用。

## 资源与复现

旧55项SVG／WAV保留。新显示家族为40张SVG与一张菜单PNG，独立放在 `assets/starfall/`；完整清单与来源见该目录。`AdventureArt.path` 只在显示层将旧素材地址映射到新地址，正式内容资源和地图数据无需改写。

```powershell
python tools/generate_starfall_art.py
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --headless --editor --import --quit
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tools/preview_art_reskin.gd -- --capture=res://reports/starfall/title.png
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tools/preview_arenas.gd -- --arena=mire --capture=res://reports/starfall/mire.png
```

生成器确定性重建SVG和清单，已选菜单PNG从项目读取并登记哈希，不重新调用图像服务。`tools/generate_assets.py` 仍用于重建旧素材与当前音频。菜单插画的生成提示单独保存，不将其来源误记为纯程序生成。

## 验证范围

源码门禁、原生场景、Windows导出和压力检查结果见[本轮验收](../reports/starfall/validation.json)。预览均为固定状态夹具，不读写个人档案，截图不代表自然难度或实体手柄试玩。macOS构建需在支持该构建流程的环境另行验证。

`./tools/test.sh`的83套Godot加5个档案入口通过，共29771条断言、40项Python测试。新增资源集成专项191条在headless、原生与导出PCK均通过；购买、合成、装符和重绘会核对真实库存、金额、UID与随机状态。另做9项原生回归，包含连续背包整理126条；导出PCK再验技能反馈与归魂环空心边界。

四地图、商店普通／满袋、标题／设置与六种技能状态共14组原生固定场景完成复核，并比较源码与PCK输出。Windows EXE已实际启动冒烟，ZIP与前包均保留本地。既有压力夹具预热5秒、采样60秒，平均113.16 FPS、P99帧间隔18.287毫秒，50次冲刺与5次Q；48项美术输入在采样前后保持，具体指纹见报告。该夹具会补血、补负载并抑制升级弹层，不代表自然难度、真人战斗识别率或长时间试玩。
