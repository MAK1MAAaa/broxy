# 大地图与小地图

## 地图与镜头

四张地图的可活动矩形统一为`Rect2(-1082,-535,3444,1800)`，面积为原`1148×450`的12倍，出生中心仍为`(640,365)`。世界、弹体、碰撞、拾取、技能与地形统一使用世界坐标，支持负坐标；没有通过缩小角色或拉伸旧背景制造空间。

新背景位于`assets/starfall/maps/expanded/`，3780×2104画布从世界`(-1146,-679)`开始，以1:1像素比例绘制。左64、上144、右272、下160的外侧装饰区域为镜头提供边缘留白：人物与八法器、符文弧及震屏完整包络在贴墙时仍避开顶栏、底栏和右上小地图。围墙沿真实可走区域边界，装饰不产生额外隐形障碍。

`ArenaCatalog`统一提供世界矩形、背景矩形、镜头中心及可见范围。运行时使用[Camera2D](https://docs.godotengine.org/en/stable/classes/class_camera2d.html)，保持原始缩放；相机的[CanvasItem.top_level](https://docs.godotengine.org/en/stable/classes/class_canvasitem.html#class-canvasitem-property-top-level)隔离世界震动，HUD仍位于独立CanvasLayer。暂停冻结镜头，停止战斗恢复中性画布。浮字、技能结果签和闪避确认按当前镜头安全区定位。

旧地图与素材清单保持。`legacy_zone_count`标明旧1280×720画布内的地形，旧生成器仅重现这一部分；新大图和正式模拟使用全部地形。沉沼、苍霜、余烬各新增8处远区地形，共11／11／12处，精确边界继续由`data/arenas.json`共享。石径和四向地面镶纹帮助辨认区域，竖立装饰位于行走范围外。

## 战斗与小地图

普通敌人从当前镜头外48像素的有效边带刷入，保持世界内24像素安全边距，每次位置选择使用固定两次随机采样。边缘与四角仍存在有效刷怪边带。距离玩家超过1800的普通敌人无奖励回收，Boss和追猎者保留；Boss围绕玩家所在区域巡航，避免探索后找不到首领。自动移动策略使用真实世界边界避让。

右上192×126小地图显示全场边界、减速地形、玩家朝向、可见视窗、普通敌人及首领／追猎者标记，不增加文字图例或操作说明。世界负坐标按长宽比映射，贴边视窗正确裁切。

小地图由现有HUD事件更新，没有独立轮询或输入处理。最多绘制128个敌人点、32处地形，优先保留Boss和追猎者。缺失或非法数据立即隐藏并清旧状态；暂停、设置、升级、商店与标题沿用现有屏幕层级，不抢键盘或鼠标焦点。

## 验证入口

```sh
./tools/test.sh
./tools/run.sh --headless --script res://tests/test_expanded_arena.gd
./tools/run.sh --headless --script res://tests/test_expanded_world.gd
./tools/run.sh --headless --script res://tests/test_minimap_ui.gd
./tools/run.sh --script res://tools/preview_expanded_map.gd -- --view=northeast --capture=res://reports/expanded-map/northeast.png
./tools/run.sh --script res://tools/preview_expanded_map.gd -- --view=boss --capture=res://reports/expanded-map/boss.png
./tools/run.sh --script res://tools/benchmark_dash.gd -- --backpack-skills --seconds=60 --output=res://reports/expanded-map/performance-raw.json
```

原生预览提供center、northwest、northeast、southeast、distant、boss、small及四个地图ID；small为960×540窗口，其余为1280×720。预览、压力夹具和自动流程均不读写个人档案。压力维持300敌人、600弹体、200掉落的旧中央合成布局，同时绘制新背景与小地图，用于性能回归，不代表全地图自然对局难度。

Windows构建使用`tools/build_windows.ps1`，更新前包保留为`build/Embers-windows-before-expanded-map-ad8c5a9.zip`。Windows环境不执行`tools/build_macos.sh`，macOS包保留历史版本。紧凑证据保存在`reports/expanded-map/validation.json`；大日志与截图留在本地。

## Windows验收

- 完整门禁90套Godot加5个档案诊断入口，31846条断言、48项Python测试通过。
- 新地图／World镜头／小地图专项181／189／47条；9套原生与9套编译PCK检查通过。包括负坐标真实弹体、相机/HUD独立性、四角完整角色包络、随机数纯性及密集敌人点预算。
- 11组原生与11组包内截图覆盖四图、中心、远区、左上／右上／右下、Boss及小窗口；各组源代码与包内像素一致。
- 5秒预热、60秒原生中央合成压力：平均91.083 FPS、P99 18.598毫秒，每步维持300敌人、600弹体、200掉落；采样真实施放落星6次、月弧10次。83项源码与资源指纹复核一致。
- 种子2026的穿透、弹射、爆破路线，默认与波间购买脉冲策略共6局均完成8波；没有据此宣称真人难度或全地图构筑平衡。
- Windows已重导出并启动EXE，更新前zip指纹保持。未重复300秒压力、未开展实体手柄验收或重建macOS。
