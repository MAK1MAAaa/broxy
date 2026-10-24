# 背包测试迁移

基线为 `a865a01` 的四法器、四备用符文、遗物三层模型。本次改成统一格子库存，不能通过保留旧容量断言来验证新规则，也不能直接忽略旧测试的失败。首次逐套审计保存在本地 `reports/backpack/audit-*.log` 和 `legacy-audit-raw.json`；后续回归使用迁移后的正式入口。

## 保留与迁移

规则、购买查询、遗物预览、符文预览、商店锁定、归魂环、内容展示和通用UI套件将伪造 `loadout/rune_bag/relic_counts` 的库存夹具换成真实购买、扩容和合成。保留错误优先级、事件次数、免费与缺省价格、预览纯查询、深复制、余额不足／已售边界、符文守恒与归魂环物理检查。遗物／符文对照套件保留弹层打开、Esc焦点返回、Tab围栏、滚动、底层交易阻断及过期回调。

原弹体、碰撞、追踪、池化、反馈、绘制、预警、暂停、设置、个人档案隔离、普通Main流程和波内升级套件继续执行。`test_combat.gd` 的测试替身增加爆破半径参数，以匹配升阶爆破的正式接口。

## 新增覆盖

| 套件 | 验证内容 |
| --- | --- |
| `test_backpack_inventory.gd` | 独立矩形oracle、边界／重叠／旋转／碎片空位、UID与价格、三类合成、双符文返还、换符、出售、扩容、属性下限、事务回滚 |
| `test_backpack_combat.gd` | 八法器×各阶、三类符文×各阶实际碰撞、多于四件与12件合法法器发射、返航、弹体池复用 |
| `test_backpack_queries.gd` | 十二遗物、八武器与三符文的各阶真实交易／预览对照，负属性及查询无副作用 |
| `test_backpack_ui.gd` | 方向键／R／Enter／Esc、原生拖拽回调、非首格抓取旋转、合成／装符／出售、满包、失败后继续整理、旧源按钮与epoch、720p布局 |
| `test_backpack_flow.gd` | 真实Main首波结束→商店→购买／合成／移动→下一波升阶武器射击→暂停／重开，不写个人档案 |
| `test_backpack_shop.gd` | 新机器人策略的真实合成／扩容、报价拒绝原因、选择顺序、快照隔离、终止与观测序列 |

## 被替代的历史套件

下列文件保留为旧模型源码，不在 `tools/test.sh` / `tools/test.ps1` 中运行。它们依赖已删除的固定槽按钮或明确冻结的旧策略，不能单独作为当前版本验收命令。

| 历史套件 | 当前替代 |
| --- | --- |
| `test_shop_actions.gd` | BackpackUI的稳定UID／选中源／快照／epoch与重复操作，购买查询事件和原子性，通用UI键盘买卖装卸，现有ChoiceActions |
| `test_shop_details.gd` | BackpackUI详情与升阶预览、BackpackQueries各阶数值对照、ContentPresentation与通用UI文字／图标／焦点 |
| `test_shop_availability.gd` | BackpackUI满格拒绝／扩容／出售／键盘、PurchaseQuery错误优先级、ContentPresentation合法满格布局 |
| `test_simulation_shop.gd` | BackpackShop与30局正式模拟；旧shop-v1的等价性要求不适用于新的backpack-shop-v2 |

测试数量变化不代表删去实际玩法要求。新行为和迁移后行为均须实跑，通过后才创建本地提交。具体次数、日志指纹及未运行平台见 `reports/backpack/validation.json` 和[背包验收](backpack.md)。
