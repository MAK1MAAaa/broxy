# 当前界面的按钮美化

本轮只调整现有《秘术余烬》的按钮显示，沿用当前像素角色、四地图与奶油纸卡界面。没有新增物品、玩法、设置或输入动作。

## 按钮分工

| 用途 | 皮肤 |
| --- | --- |
| 进入试炼、下一波、购买、强化、继续 | 深青绿珐琅、奶油白文字、深底边与浅高光 |
| 设置、返回、刷新、移动、旋转、出售 | 奶油圆角、深蓝文字、轻投影 |
| 起始法器与地图选择 | 浅色圆角卡，选中时加深边框和面色 |
| 锁定／解锁 | 紧凑小按钮，已锁用主色，保留明确文字 |
| 缺钱或放不下 | 低强调灰绿，仍可聚焦并显示原拒绝原因 |
| 已购买／未解锁 | 原禁用状态，移除投影并降低强调 |

`scripts/ui/button_skin.gd`集中提供五种角色、六种完整状态（普通、悬停、按下、选中悬停、禁用、焦点）。普通圆角8px、主按钮10px、紧凑按钮6px；实底边和最多2px投影增加体积，按下时取消投影，内容下移2px且上下边距之和不变。主按钮文字在普通／悬停／按下背景的静态sRGB对比度约5.57／4.84／7.34。

焦点独立绘制边框与两侧菱形，不只依赖色差。紧凑标记收在6px内容边距内，避免覆盖中文。`ButtonFinish`是忽略鼠标、不能聚焦、不逐帧处理的装饰控件，仅响应按钮绘制、尺寸和状态事件；重复应用皮肤复用原节点与连接，不连接业务`pressed`信号。

皮肤通过按钮实例局部覆写接入，未向全局Button主题加入新状态。背包物品格继续使用原矩形盒、材质、阶级、装符和共鸣样式。原按钮名称、回调、焦点标识、购买条件和布局容器保留，设置中的两个开关也使用同一套圆角背景；音量滑轨沿用。

## 原生预览

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tools/preview_button_polish.gd -- --view=title --capture=res://reports/buttons/title.png
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tools/preview_button_polish.gd -- --view=locked --capture=res://reports/buttons/locked.png
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tools/preview_button_polish.gd -- --view=pressed --capture=res://reports/buttons/pressed.png
```

`--view`还支持settings、controls、pause、shop、poor、sold、upgrades、hover。夹具使用正式GameUI、购买与锁定API，预算与商品为固定条件，不读写个人档案；暂停弹层置于固定标题背景，不代表自然暂停对局。hover／pressed先将引擎鼠标定位至正式主按钮，再发送GUI事件，并断言实际DrawMode后捕获，按下图停在释放之前，不启动新对局。

标题与商店支持`--small`，使用960×540实际窗口与1280×720逻辑画布，保存的仍是1280×720视口图，不将其误称为540p屏幕截图。样式为原生Godot代码绘制，没有新增位图、SVG、字体、着色器或外部依赖。

验证日志、源码与导出PCK画面对照、Windows包指纹见[本轮验收](../reports/buttons/validation.json)。本轮不重做战斗压力采样、完整自动对局、实体手柄或macOS构建验证。

完整`./tools/test.sh`门禁83套Godot加5个档案入口通过，共29771条断言、40项Python测试。另做9项原生专项，覆盖菜单／模态、锁定、键位、软件手柄导航和连续整理；导出PCK再验4项，包括连续整理126条。13组固定画面的源码／PCK PNG逐字节一致，悬停／按下使用真实DrawMode检查，独立视觉复核未发现小按钮压字或阴影侵入邻卡。

Windows EXE已实际启动冒烟，ZIP的CRC、5成员字节与x64 PE检查通过。按钮美化前的包保留为`build/Embers-windows-before-button-polish-fe97510.zip`；旧素材、地图、战斗、声音与背包物品格文件保持原字节，未生成新美术文件。
