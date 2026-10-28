# 全屏动画封面

本轮按更新后的 `AGENTS.md` 重设计封面：解释性文字意味着界面不够直观，应调整布局、图标与状态，不能用追加小字弥补。删除起始法器定位／解锁小标签、法器介绍、最佳记录与空记录、底部键位说明及地图地形副文案，也移除对应封面tooltip；保留标题、物品／地图名称与必要操作。

所有交互集中在左侧520px：四个法器、2×2地图、进入试炼、设置和退出。缩略图表达地图，勾选标记表达当前选择，锁形标记与禁用态表达未解锁。选择后仍传递原法器与地图ID，原键盘、鼠标、手柄、模态与焦点路径保留。详细键位位于操作设置，HUD继续按实际输入设备显示技能键。

横向底图覆盖完整1280×720逻辑画布，人物和月环在右侧，左侧使用连续渐隐遮罩保障操作文字对比度；不再拼接半幅插画与纯色背景。来源与完整提示词见 `assets/title/PROVENANCE.md` 和 `image-generation.json`。

## 动图与播放

`assets/title/cover.gif` 是实际24帧GIF，每帧120ms，2.88秒无限循环，包含右侧星尘、环光点、烛火与地面符印呼吸。底图、人物与相机不移动。游戏通过同一 `TitleCover` 原生绘制器播放相同24帧状态，单个Timer驱动，隐藏／换页时停表或释放；不读取档案、不改变游戏规则或RNG。

Godot官方[纹理格式列表](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html)未列GIF，且[AnimatedTexture已弃用并存在当前版本问题](https://docs.godotengine.org/en/stable/classes/class_animatedtexture.html)。本轮因此交付GIF并复用原生帧状态，分发包明确收录GIF，不增加解码插件。每个动作帧最多83个绘制原语，只在120ms换帧时重绘；不进行逐帧模拟或全图纹理切换。

## 复现

封面底图已保存，只有重新生成或编辑底图才需要图像服务。GIF重建使用原生引擎与可选美术工具依赖（游戏运行及Python素材测试不依赖Pillow）：

```powershell
python -m pip install -r tools/requirements-art.txt
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tools/render_title_cover.gd -- --output=res://reports/title-cover/frames
python tools/package_title_cover_gif.py
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tools/render_title_cover.gd -- --ui --output=res://reports/title-cover/ui-frames
python tools/package_title_cover_gif.py --frames reports/title-cover/ui-frames --output reports/title-cover/title-preview.gif --metadata reports/title-cover/ui-animation-raw.json
```

底图保持稳定，共享调色板预留一个透明索引仅用于GIF帧差分。全部帧（含首帧）使用同一固定调色映射，显式写入透明差分，关闭自动重索引，防止首帧与后续帧的静态色跳。编码后重新解码全部24帧，逐像素等于固定调色后的源帧，并验证原生静止像素在GIF中也不变；原生帧24与帧0完全一致。GIF的255色量化与原生全色绘制存在格式色差，不宣称两种格式的PNG字节相等。

## 验证

新增专项验证真实Timer播放、停播、循环、隐藏／恢复、换页销毁、原生帧像素变化，以及键盘选法器、鼠标选地图、模态焦点和开始信号。旧键位／设备测试迁到实际操作设置与HUD，继续核对合法绑定、技能时钟和精确按键，不为旧用例保留隐藏小字。

完整源码、原生／导出PCK、GIF、Windows包与原素材保持的验收记录见[本轮报告](../reports/title-cover/validation.json)。固定菜单状态与软件输入不代表实体手柄试玩；本轮不重跑战斗压力、完整自动对局或macOS构建。

完整`./tools/test.sh`的84套Godot与5个档案入口共29837条断言通过，43项Python测试通过。封面专项headless66条、原生72条通过；旧UI、设备、键位与解锁选择专项完成原生回归。GIF编码最终调整后重新运行43项Python及原生封面专项，静止区首尾色差为0。
