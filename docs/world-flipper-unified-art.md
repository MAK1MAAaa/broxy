# 敌人与封面原作换装

本轮继续统一当前游戏的原作素材：五类敌人分别采用蓝波露、帕拉鼠、魔像、火精和瑞西塔尔；封面改为官方菱格背景与阿尔克完整立绘，移除原鸟喙插画在当前封面的使用。来源与版权见 [素材记录](../assets/worldflipper/PROVENANCE.md)，逐文件校验见 [manifest](../assets/worldflipper/manifest.json)。旧 `assets/starfall/`、`assets/title/` 资源原样保留。

敌人仍通过 `AdventureArt` 映射到既有ID，保留绘制画布与世界包络；最近邻整数倍放大，透明度不插值，脚底对齐现有贴地影。碰撞、招式预警、受击、减速、脉冲、刷新与奖励逻辑不变。

封面采用独立背景与肖像层，右侧槽位 `(660,16,600,688)`，完整保留头发和脚部，并在窗口四边内留出空间。非像素立绘局部使用线性过滤，像素素材继续nearest。24帧／120毫秒循环由唯一计时器驱动，星芒、光点和轻轨迹使用确定性状态；隐藏或释放封面会停表或清理。图层不接收输入，原地图／法器选择、设置、键盘与手柄焦点继续工作。

运行时GIF为 `assets/worldflipper/title/cover.gif`；`animation.json` 同时记录背景、阿尔克原图、渲染脚本和来源清单的SHA，固定共享调色板编码并核对静止像素。原有GIF路径保留历史文件，新导出预设显式包含当前GIF、元数据与原作声明。

## 生成与验证

```sh
python -m pip install -r tools/requirements-art.txt
python tools/fetch_world_flipper_art.py --offline --references
./tools/run.sh --script res://tools/render_title_cover.gd -- --output=res://reports/world-flipper-unified/frames
python tools/package_title_cover_gif.py --frames reports/world-flipper-unified/frames
./tools/test.sh
```

首次获取原图时去掉 `--offline`。Windows也可使用 `tools/run.ps1` 与 `tools/test.ps1`；传给Godot的分隔符写为 `'--'`。原始下载保存在 `.tools/worldflipper/source/`，不进入源码。敌人与封面规范化模块在写入前校验来源SHA、尺寸和边界，图片与GIF保留各自的来源记录。

`tools/preview_world_flipper_unified.gd` 使用真实购买、背包扩容和正式敌人生成，在四张地图固定展示五类敌人；冻结后核对绘制不改变库存、战斗与随机状态。完整检查摘要记录于 `reports/world-flipper-unified/validation.json`。

Windows包更新前保留 `build/Embers-windows-before-unified-art-0931fcf.zip`。macOS本轮仅检查构建入口，未构建或运行应用。

本轮 `./tools/test.sh` 完成95套Godot测试与5种诊断，共33,346条断言，另49项Python测试，均无失败。16套原生与相同16套PCK检查通过，33组源码／PCK截图逐像素相同；20个不同缓存源文件、17张运行图片与当前GIF的校验一致。GIF为1280×720、24帧、120ms／帧，静止像素与固定调色板解码结果均核验通过。Windows构建、EXE启动、ZIP中10个文件的CRC及发行目录字节比对通过，原作声明与源码一致，旧包SHA与上一轮记录一致。

核心规则、角色存档逻辑、目录数据和既有程序美术未变。未执行macOS导出、战斗压力基准、硬件手柄或硬件音频验收；测试仅对实际运行过的检查作结论。

## 多主角范围

用户已明确本轮先完成敌人与封面，角色机制另议。因此未加入抽取、招募货币、持久化角色库、主角选择或初始武器差异。已核对的克拉莉丝、希尔媞和花火素材、归一化工具与对照图只保存在本地 `.tools/worldflipper/candidates/`，不纳入当前源码和发行包。
