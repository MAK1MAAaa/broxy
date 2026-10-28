# 技能音效与命中反馈

冲刺、脉冲与成功闪避此前复用了同一段符文音效；本轮按动作与实际结果区分短音色，并让Q是否真正受控可见。战斗数值、冷却、背包与随机规则保持。

| 实际事件 | 声音与视觉 |
| --- | --- |
| 冲刺启动 | 0.18秒风切声，原残影保持 |
| Q未控住敌人 | 0.28秒空心低频声，0.45秒“未受控” |
| Q实际控住普通敌人 | 0.34秒带短促接触层的脉冲声，0.45秒“受控 ×N” |
| 冲刺保护实际挡伤 | 0.22秒双泛音确认声，原“闪避”提示保持 |
| 实际承伤 | 原承伤声和视觉优先，停止此前的闪避确认尾音 |

四段WAV为标准库原创确定性合成，原始文件均为22050Hz、单声道16-bit PCM，独立淡入淡出且不循环；来源与CC0见`assets/PROVENANCE.md`。新音源由`tools/audio_skills.py`在旧素材之后生成，不改变旧共享随机序列。原51项SVG／WAV字节保持，当前共55项，连续生成两次完全一致。

## 关键音保护

仍使用12个SFX播放器，环境音另占1个播放器。普通音优先级0、技能1、成功闪避2、承伤3；轮转寻找未保护槽，满池时只允许更高优先级替换最低级最旧声音，否则丢弃新请求，不排队、不写接受时间。保护同时检查WAV时长与实际`playing`，避免音频线程迟起时过早覆盖尾音。

`play`／`play_cue`保留原键名和100／35毫秒节流。Master静音时不启动新声音；结算与新波停止战斗关键音，普通界面声和环境音保留。暂停期间不产生新战斗请求，已播短尾按墙钟自然结束，恢复不补播。音量与静音继续由原设置统一控制。

## 受控结果签

结果只读取正式施放的实际`affected`，不扫描敌人猜测“免疫”。0既可能为空放，也可能仅遇首领／追猎者，因此显示“未受控”；正数包含受控但受边界限制无法完整位移的敌人，统一称“受控”。不增加伤害、掉落、冰霜或保护。

结果签为独立单槽，在施法点下方短暂显示，靠下缘时移到上方并安全限边；字体宽度在施放时缓存。关闭闪光仍保留静态文字，原0.30秒范围线与可选内圈保持。成功闪避或真实承伤立即撤签，最近计数仍可观察，重复信号不会复活；暂停冻结，停止／新波清空。绘制在玩家之后、承伤与敌方危险之前，危险信息可能遮住部分结果文字。

## 复跑

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tests/test_skill_audio.gd
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tests/test_skill_feedback.gd
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tools/preview_skill_feedback.gd '--' --case=hit --capture=res://reports/skill-feedback/hit.png
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 --script res://tools/preview_skill_audio.gd '--' --output=res://reports/skill-feedback/engine-mix.wav
```

画面另有empty、flash_off、danger、hurt和corner，使用正式Main与施放／碰撞路径的固定夹具，关闭存档，不代表自然对局难度。视觉预览静音，声音由独立原生专项与引擎混音检查。

混音文件为约6秒的孤立SoundBank试听：独立音色、双技能与普通音叠加、成功闪避及随后承伤取消。临时总线按顺序应用0.65增益再捕获，Master为单位增益并恢复原状态；这等效于该孤立线性场景的默认音量，不是完整对局、麦克风或扬声器回录。原生混音48kHz立体声PCM无削波、非有限样本或缓冲丢帧。自动检查不等同于扬声器听感验收。

## Windows验收

`./tools/test.sh`的82套Godot与5个档案入口，共29580条断言、35项Python测试通过。技能音频专项headless48条、原生54条，结果反馈原生76条通过；旧声音、冲刺、闪避、脉冲专项另做原生回归。headless默认仍无音频，声音调度专项明确注入真实资源。半速播放只用于测试晚结束的真实声部，生产音高保持默认。

六组1280×720固定画面已独立复核，源码与导出PCK截图逐字节相同。受控3个、未受控0个、关闭闪光、场角避让、危险保留及承伤撤签符合正式状态；危险场景部分结果文字被敌弹遮挡，符合危险优先，不据此推断所有密集场景的人类可读性。

源码与PCK均实际导出约6秒引擎混音，13阶段请求均接受，采样无削波或缓冲丢帧，临时音频状态恢复。两者载入的13种SFX导入数据逐字节相同；导入数据格式随Godot压缩记录，不将其误称为原始PCM。两个捕获WAV不要求样本级一致，调度标记也不是样本精确边界。自动检查不替代主观听感，未做扬声器试听，可用生成的`engine-mix.wav`复核。

默认设置、两件真实合成的Ⅲ阶技能遗物与八法器合成压力预热5秒后采样60秒：平均114.06 FPS、P99帧间隔18.06毫秒，50次冲刺均确认挡伤，5次Q累计受控394次。结果签采样峰值1，关键音同时播放峰值3；该压力仅观察到dash／evade／pulse_hit，空放由专项和稀疏预览另验，没有为了空放改变原压力摆位。采样第15秒实际置前观察窗口。

压力指纹同时记录82项输入，其中17项为14段WAV、清单及两个音频生成器，前／后／当前一致。夹具仍补血、补足300敌人／600弹体／200掉落、为真实冲刺加入敌弹，并抑制升级弹层，不是自然难度或真人胜率。

Windows重新导出并实际启动EXE冒烟；匹配引擎加载导出PCK的54条音频与76条反馈、六画面及独立混音全部通过，外部夹具与普通EXE分别记录。ZIP CRC、5个成员字节及x64 PE通过，前包保留。原51项资源与433个非当前素材元数据的既有文件保持，当前清单／来源更新为55项；65个核心／战斗／数据文件保持原字节，仅声音调度与World呈现发生变化。

证据见[完整验收](../reports/skill-feedback/validation.json)、[音频与混音](../reports/skill-feedback/audio.json)及[压力采样](../reports/skill-feedback/performance.json)。本轮未重建macOS、重跑完整自动对局或300秒采样，也未接实体手柄。
