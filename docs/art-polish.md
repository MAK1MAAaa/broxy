# 材质与贴地层次

## 视觉目标

沿用当前明快像素风，以沉沼的实际战斗画面为代表目标：背景保持低对比，角色用清晰暗边和材质高光辨认，脚下保留接触关系，暖色敌方危险信息优先。界面不追加解释小字。

六角色使用`upper-left-light-02`内部材质：象牙面具、兜帽与披风、游魂褶皱、兽面、石甲盾面、术士骨杖和首领金冠祭袍。画布、支点、透明轮廓、原像素网格和运行时尺寸均保持。Python源图及实际导入纹理共同验证，不改变碰撞或受击形变。

四地图使用`expanded-arena-02`材质：96／112／144／160像素的长短石板与48／56／64像素变行，接缝降低对比，选择性磨损和高光保持4像素簇。祭坛石刻与柱体、沉沼湿苔与反光、霜庭冰裂与冰晶、余烬碎屑与分层岩块形成场景差异；远区地面镶纹及外缘守石补充刻纹、侧面与底座。

3780×2104背景、世界原点、全部34处减速椭圆及可活动范围沿用大地图规则。地面细节为平面纹理，竖立装饰在可走区域外；没有新增隐形障碍或红色危险伪提示。来源与授权分别记录在`assets/starfall/PROVENANCE.md`和`assets/starfall/maps/expanded/PROVENANCE.md`。

## 运行时呈现

`GroundingPainter`以一个无纹理ArrayMesh和一个固定MultiMesh批量绘制三条深蓝横带，形成浅边、深芯的像素接触影。容量761，等于340敌人、420掉落与玩家；最多一次绘制，没有每实体新增节点。仅投影当前视窗外扩96像素以内的有效对象，重建不写模拟数据或随机数。

玩家脚影固定在身下12像素，敌人按身体尺寸投影至脚底，首领略扁宽；魂屑按分值使用两种小影。阴影不随角色呼吸、受击压扁或魂屑浮动而移动，让悬浮高度可见。

顺序为背景／气氛／技能地面范围、接触影、玩家法阵、魂屑、敌人及友方攻击，然后输出特效与角色前景；承伤、敌方弹体及预警继续最后绘制。玩家光斑透明度降到0.16、法阵0.24±0.03，Boss光斑0.13±0.02，避免贴身敌人脚部被光效抹平。稳定接触影在关闭闪光时保留，暂停不推进状态，停止与结算清空批量实例。

## 验证入口

```sh
./tools/test.sh
./tools/run.sh --headless --script res://tests/test_grounding_painter.gd
./tools/run.sh --headless --script res://tests/test_art_grounding.gd
./tools/run.sh --script res://tools/preview_expanded_map.gd -- --view=mire --capture=res://reports/art-polish/mire.png
./tools/run.sh --script res://tools/preview_expanded_map.gd -- --view=boss --capture=res://reports/art-polish/boss.png
./tools/run.sh --script res://tools/benchmark_dash.gd -- --backpack-skills --seconds=60 --output=res://reports/art-polish/performance-raw.json
```

原生预览使用真实地图、角色、魂屑、镜头和小地图，并关闭个人档案读写；压力维持旧中央300敌人／600弹体／200掉落的合成布局。原始大日志和截图留在本地，紧凑证据保存在`reports/art-polish/validation.json`。

Windows使用`tools/build_windows.ps1`重新导出，更新前包备份为`build/Embers-windows-before-art-polish-8ed662b.zip`。Windows环境未执行`tools/build_macos.sh`，macOS包保留历史版本。

## Windows验收

- 完整门禁92套Godot加5个档案诊断入口，31899条断言、49项Python测试通过；新投影与场景集成专项33／20条。
- 9套原生与9套编译PCK专项通过，覆盖真实绘制、满池复用、状态纯性、暂停、闪光关闭、清理与威胁层级。ArrayMesh颜色按8位量化容差检查。
- 15组源代码与15组包内原生截图覆盖四图、中心、远区、边缘、首领、小窗口及四种镶纹，像素一致；另检查源代码和包内的危险／闪光关闭画面。
- 六张角色图逐点对比更新前SVG，透明轮廓、画布与支点保持，内部材质颜色有实际变化。
- 5秒预热、60秒中央合成压力平均83.841 FPS、P99 18.427毫秒；每步维持300敌人、600弹体、200掉落，接触影采样峰值501、容量761、最多一次绘制。90项源码与资源指纹复核一致。
- 固定种子2026、三条符文路线的默认／购入脉冲策略共6局，除版本标识外所有输出字段与上一版一致，均完成8波。
- Windows包重新导出并启动EXE，更新前zip指纹保持；未重复300秒压力、实体手柄验收或macOS构建。
