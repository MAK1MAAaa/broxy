# 阿尔克与武器换装

本轮在当前游戏中直接使用用户指定的《弹射世界》角色和武器素材。主角为阿尔克，八件武器的原图与当前物品外观映射记录在 [素材来源](../assets/worldflipper/PROVENANCE.md)，逐文件下载地址与SHA-256见 [manifest](../assets/worldflipper/manifest.json)。原图保留原作版权，未标记为开源、CC0或官方授权。

## 接入

`AdventureArt` 只为玩家与八件武器增加精确PNG路由。已有美术资源保留，正式购买、合成、符文、物品ID和数值继续使用原规则。阿尔克使用原24×30待机与前后步行GIF，最近邻放大3倍后对齐旧角色脚底，68×68世界绘制包络、碰撞与阴影位置不变。步行一周期0.38秒，保留80／100／100／100毫秒；水平移动时镜像正面，向上移动用背面。

动画只读取现有视觉时间和移动方向，暂停及失焦沿用原冻结逻辑，不消费战斗随机数。冲刺起步按冲刺方向采样；每个固定池残影保存帧号与镜像，不随当前角色切帧跳动。关闭闪光沿用原残影开关。商店、背包、HUD、详情与环绕武器统一使用新PNG，背景、敌人与弹体仍保留当前作品的既有美术。

## 获取与重建

Python 3.10+及Pillow环境执行：

```sh
python -m pip install -r tools/requirements-art.txt
python tools/fetch_world_flipper_art.py --references
python tools/fetch_world_flipper_art.py --offline --references
```

第一条读取固定清单并校验源文件SHA-256；第二条只用本地已验证缓存。原始图、完整角色立绘、41帧技能GIF与素材对照图保存在 `.tools/worldflipper/`，不纳入源码。运行所需9张PNG与1张图集单独保存于 `assets/worldflipper/`。项目没有用技能GIF替代走路动画。

两平台导出包含原作声明与素材清单，发行目录新增 `licenses/World-Flipper-NOTICE.txt`。Windows包更新前的备份为 `build/Embers-windows-before-world-flipper-fea5438.zip`。验证摘要保存于 `reports/world-flipper/validation.json`；原生与PCK预览保留在同目录的本地忽略文件中。macOS本轮只检查构建入口，未构建应用。

## 本轮验证

- `./tools/test.sh`：95套Godot测试与5种诊断，共33,331条断言，另49项Python测试，均无失败。
- 15套专项原生检查及相同15套PCK检查通过，覆盖角色动画、冲刺、玩家绘制层、贴地影、字体、背包与正式交易。
- 29组源码／PCK预览逐像素相同，包括商店、背包整理与详情、技能、原作武器陈列和战斗。
- 14份已固定下载源与10个运行图片的SHA-256、尺寸、透明范围及GIF时序核对通过。PNG按无损、无mipmap、无透明边缘颜色扩展导入。
- Windows构建、EXE启动、ZIP的10文件CRC与发行目录逐字节比对通过；外置原作声明与源码一致，旧包SHA-256与上一轮记录一致。
- 核心规则、目录数据与既有程序美术未变。macOS构建脚本仅静态检查；未运行战斗压力基准、硬件手柄或硬件音频验收。
