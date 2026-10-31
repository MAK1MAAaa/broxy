# 日服资源缓存与真实地形准备

本轮取得1230份真实JP地形原始字节，按精确`terrain_ref`绑定最终目录1422条布局引用，全部通过ZIP CRC32、实测SHA256与AMF3完整解码。其几何可保留为1465个独立层、23394条普通WALL开放段；这属于可追踪的原始数据准备，**没有因此新增竞技场**。当前仍为七张素材主题宽地图，加三张官方试玩原布局适配，共十张可玩竞技场。

## 来源与版本证据

来源为公开保存项目[gacha-archive](https://archive.org/details/gacha-archive)，[元数据入口](https://archive.org/metadata/gacha-archive)列出的文件为：

```text
Online/World Flipper/air.jp.co.cygames.worldflipper-1.780.0.1780000.zip
```

归档大小6,861,267,373字节。文件名描述客户端包版本，不能拿它推断每份游戏资源版本。实际提取的`asset_download/production/info.json`共226字节，SHA256为`96991a8f2ff0531b0b8b50fd564c0245721493c85cb2cf3605e6a5830a1861fb`，其中声明缓存版本`1.780.30`、`assetSizeKind=fulfill`及2024-01-23资源归档时间。

项目目录基准仍是[固定JP最终归档1.780.40](https://github.com/blead/wf-assets/tree/1d45b529ef078ba9b1f876d4588debd0c8a9a214)。新缓存中的1422条`field_data`与247条`field`原行逐字段匹配该目录；426件装备的目录已记录列也逐字段匹配，没有比较目录未保存的说明列。这些证据证明了引用与表内容的对应关系，尚不能证明每份PNG、地形或图集都与最终1.780.40逐字节一致。

未下载完整6.86GB ZIP，也未独立验证上传者提供的全包SHA1；注册表明确保留`whole_archive_checksum_verified=false`与`final_jp_byte_identity_verified=false`。缓存声明版本也不自动成为每个对象的独立版本证明。

## 已验证范围

| 资源或阶段 | 本轮实际范围 | 状态 |
| --- | --- | --- |
| ZIP64中央目录 | 136289条目，30716874字节 | 实测SHA256固定 |
| 精确地形资源 | 1230个唯一引用，原字节合计1731439 | 全部CRC／SHA／AMF3验证 |
| 最终目录布局引用 | 1422条，均能绑定上述地形 | 引用闭合，不是1422张已实装地图 |
| 地形几何 | 1465层，23394条普通WALL开放段 | 保留独立层、原始偏移与开放折线 |
| 场景配套样本 | 草地、兽界荒地、雪原各PNG／atlas／parts／timeline，共12份 | 已取真实字节并解码 |
| 全部正式注册资源 | 1247份，原字节合计2557670 | 全部离线复核通过；1240份AMF3完整解码 |
| 当前可玩地图 | 原七张宽图＋三张试玩原布局 | 仍为10张 |

中央目录实测SHA256为`3e7b2893cd09a3d200b597eeedd1bf6f1f3542cd0e031fdb1d9e4d77b64d4e62`。每份资源的逻辑路径、盐化路径、ZIP偏移、方法、大小、CRC32与原字节SHA256锁在[独立来源注册表](../tools/world_flipper_jp_archive_sources.json)，不靠文件名猜测身份。工具使用已有提取器公开的路径映射格式，但不把工具代码许可当作原游戏资产许可。

场景样本分别绑定`tree_grass01_1_2`、`beast_barren`、`snow_plain`的精确背景引用。原PNG为274×738，atlas中的272×736内容位于(1,1)，parts与timeline独立保存。另从中央目录精确索引到229个field的背景PNG及atlas、233个field的parts与timeline；其余背景尚未批量取得和验证，不能将这些索引数计作资源实装。前轮2022镜像132张背景对应198个field引用的成果仍是独立历史来源，也不等于198张地图。

## 几何与当前地图的差别

原始AMF3保留对象组、可见标记、位置、宽高、旋转、折线与层号。普通WALL只取相邻顶点形成开放线段，不自动首尾封闭；BOUNDS是映射边界证据，不推断成隐式墙。各层分别表示地形阶段，不能叠到同一碰撞场景中。部分布局含重复BOUNDS、多层与原始偏移，需要逐图决定运行映射。

原始对象中还有222个`WALL1`、24个`WALL2`及24116个道具锚点。编号墙的激活语义、单向墙与各类弹板、可破坏物、重力区、传送及其他机关行为尚未完整解释；道具编辑器椭圆也不自动等于实际碰撞形状。所有数据保留在解码结果中，不为未知机制添加通用圆障碍来冒充原作。

已有三张试玩原布局的对照为：

| 原布局引用 | 本JP缓存证据 | 与已用试玩源的关系 |
| --- | --- | --- |
| main_2_9_5 | layer0，3条普通墙段 | 归一几何一致，不代表原始字节一致 |
| main_6_6_2 | layer0，6条普通墙段 | 归一几何一致，不代表原始字节一致 |
| main_3_6_2 | layer0有11条、layer1有8条普通墙段 | 试玩仅一层；其层号不能直接沿用为JP层号 |

船舱试玩层0的BOUNDS对应JP层1附近，但道具与对象数量仍有差异。当前`jp_ship_3_6_2`继续使用已经验收的试玩层0；没有静默替换为JP层0、合并两层或覆盖背景。旧94张运行PNG、原有十张地图和既有碰撞配置保持，新归档仅为后续逐图适配提供真实依据。2022镜像神社同引用原图的像素版本差异也已保留，不用历史镜像覆盖当前地图。

## 下载、离线复核与缓存

[提取工具](../tools/world_flipper_jp_archive.py)只需Python 3.10+标准库。先核固定ZIP64中央目录，再用精确HTTP Range提取注册条目；严格检查206、Content-Range、局部ZIP头、大小与CRC。最多4并发，默认3；429、部分5xx及网络错误最多重试3次。路径逃逸、加密或符号链接成员、超大输入、未知AMF3类型、非有限数、引用展开超限及尾随数据均拒绝或明确记录，不执行来源中的代码。

首次准备中央目录需要约30.7MB；1230个地形的Range初步合计2990959字节，不含重试。全部1247个注册资源的Range估算为3769031字节；另有版本元数据的小片段。无需为了这些资源下载完整6.86GB归档。工具每批限制64MiB估算预算，逐项保存凭据，失败清单与退出码保留；续跑复用已验证缓存。

```powershell
python tools/world_flipper_jp_archive.py --download --kind terrain --workers 3
python tools/world_flipper_jp_archive.py --kind terrain --workers 3
python tools/world_flipper_jp_archive.py --kind all --workers 3
python -m unittest discover -s tests -p test_world_flipper_jp_archive.py
```

默认离线，不带`--download`不会补取资源。首次要取得全部样本可使用`--download --kind all`。中央目录、原始字节、逐项CRC／SHA证据及解码JSON只进入被忽略的`.tools/wf-full-map-research/jp-archive/`；源码仅纳入工具、固定来源注册表和测试，不纳入大型原始缓存。文本输出为UTF-8 LF。

本地已完成15项该工具Python测试，以及1230份地形和1247份全部注册资源的离线复核，失败为零；原始报告留在上述缓存的`all-terrain-verified.json`、`all-registered-assets-offline.json`和`terrain-geometry-inventory.json`。无缓存环境会明确跳过实际原始缓存复核，不把跳过写成原图已下载。上述结果没有运行新地图、Godot完整回归、打包或性能采样，也不证明全目录玩法完成。

后续需要逐布局核对地图阶段、背景parts、机关定义、碰撞可达性与当前自由移动玩法的映射，再接入运行目录并独立验收。权利与素材范围见[原作素材来源](../assets/worldflipper/PROVENANCE.md)和[NOTICE](../assets/worldflipper/NOTICE.txt)。
