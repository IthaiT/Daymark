# 记账存储与验收说明

记账使用独立的 `ledger.json`，共享数据目录及现有 `.daymark.lock`。时间记录的 `tags.json` 版本 1、CSV 六列及 UTF-8 BOM 保持不变。

## 版本 2

以下为合成示例，现金开账 10,000 元，已支付午餐 28 元。金额为整数分；日期是本地日历字段，无时区转换。

```json
{
  "version": 2,
  "default_cash_account_id": "cash",
  "balance_enabled": true,
  "category_presets_version": 1,
  "accounts": [
    {"id": "cash", "name": "现金", "kind": "cash", "opening_cents": 1000000, "balance_cents": 997200},
    {"id": "provident", "name": "公积金", "kind": "provident", "opening_cents": 0, "balance_cents": 0},
    {"id": "investment", "name": "投资", "kind": "investment", "opening_cents": 0, "balance_cents": 0}
  ],
  "categories": [
    {"id": "food", "name": "餐饮", "kind": "expense", "parent_id": null, "color": "green"},
    {"id": "lunch", "name": "午餐", "kind": "expense", "parent_id": "food"}
  ],
  "records": [
    {"id": "example", "kind": "expense", "amount_cents": 2800, "date": "2026-10-11", "category_id": "lunch", "notes": "", "account_id": "cash", "to_account_id": null, "affects_balance": true}
  ],
  "pinned": ["lunch"]
}
```

- 收支 `kind` 为 `expense` / `income`，金额大于零。可使用任意同类型分类，也可为未分类（`category_id: null`）。普通新增收支的账户固定取 `default_cash_account_id`。
- 转账 `kind: transfer`，金额大于零，明确保存不同的转出、转入账户 ID，分类为空。两个账户影响相抵，资产总额不变。
- 校准 `kind: adjustment`，金额为实际余额减去校准前账面余额的有符号差额，分类为空。它是可撤销的调整记录，撤销或删除恢复该差额；后续编辑其他流水不会重新解释为绝对目标余额。
- 所有记录保存 `affects_balance`。旧流水为 `false`；启用后新建收支为 `true`，补记日期再早也正常联动。修改旧流水保留原关联标志。
- 账户 ID 不随名称修改而改变；账户 `kind` 仅用于说明，不用来猜测默认账户关联。
- 分类为独立的收支树，不能形成环、不能跨收支类型移动，同级名称按现有 Unicode casefold 校验。分类 ID 不随名称或父节点改变；存在子分类或流水关联时不可删除。
- `pinned` 为支出分类 ID 的有序列表；普通收入通过次级入口录入。
- 同日流水以数组中创建顺序的逆序显示，修改不改变创建顺序；跨日按记录日期降序显示。

控制器串行处理 mutation、原子写入及快照历史。余额由 `opening_cents` 加明确关联记录的影响计算，保存一次完整快照；成功后再发布内存状态。失败时不推进撤销/重做历史、不清空输入。读取时验证每个账户余额、关联 ID、分类树、日期及整数金额；损坏文件和未知版本不会被覆盖。

## 版本 1 兼容边界

保留并测试以下旧格式兼容契约；不读取或推测个人数据。

版本 1 使用上述 `accounts/categories/records/pinned` 列表，但账户只需 `id/name/kind/balance_cents`；收支只需 `id/kind/amount_cents/date/category_id`，备注可省略，没有余额影响信息。`default_cash_account_id` 可显式提供，缺省仅识别稳定 ID `cash`，不按名称或类型推断。

加载版本 1 时：

1. 每个账户现存余额作为开账余额，所有历史收支保留并标记 `affects_balance: false`。原有账户关联保留，缺失关联补为显式默认现金 ID。
2. 不立即重写文件。直接保留原余额；首笔新增、删除或资金操作自动启用后续余额联动并一次原子写入版本 2，不再要求初始化资金。旧版版本 2 中 balance_enabled 为 false 的账本采用相同行为。
3. 修改、删除旧收支不改变余额；新补记流水明确关联现金并影响余额。

该兼容契约针对没有自动余额联动的历史收支，不接受缺少明确账户关联的转账或校准；不支持猜测其他未提供的旧格式。现有版本 2 的余额和明确关联字段继续保留，不回放历史流水。

## 验收对应

`test/ledger_test.dart` 验证整数金额、10,000 → 9,972 → 10,972 元、收支类型修改、删除、批量、串行写入、撤销/重做、转账守恒、校准差额、多层分类移动汇总、默认账户关联、升级不重扣、跨月补记、失败回滚和损坏文件保护。

`test/ledger_widget_test.dart` 验证零余额直接录入、日期箭头、备注失败保留输入、标签折叠／右键颜色／拖动、月年收入与支出统计、Enter 跨收支类型批量录入、上下键金额框导航、输入框原生撤销动作、Tab 金额框切换、Ctrl+Z/Y、批量写入、弹窗失败保留金额和备注、转账及校准、分类新增/移动/固定/顺序、月份与逐层占比、滚动自动扩展、模式切换及 1100×740 布局。截图使用合成记录和系统字体，输出到 `.test-artifacts/ledger.png`、`.test-artifacts/ledger-statistics.png`。

`tools/smoke_windows.ps1` 在不可激活的私有 Windows 桌面验证 Release 启动、窗口边界、时间 CSV 的 BOM/跨午夜空档、已联动记账文件不被回放改写、第二实例拒绝和退出释放共享锁。所有数据位于 `.test-artifacts/`。

## 彩色标签与统计

标签可选 `color` 字段为 Material 色系名称：`green/teal/cyan/blue/indigo/purple/pink/red/orange/amber/lightGreen/blueGrey`。缺省或 null 继承最近显式设色的祖先，未设色的一级标签使用稳定的默认色系；子标签按树中顺序使用不同色阶，相同色系的一级标签也区分色阶。统计图使用柔和的 Material 色阶，住房与交通分别使用青绿色和浅青色；徽标将对应强调色混合到白色底上，以深色同系图标或深灰前景保证 4.5:1 对比度。非法颜色拒绝读取，改色、移动、重命名不改变 ID。

`category_presets_version: 1` 标识已补充本次默认分类。不含此字段的旧文件先完成原数据校验，再在内存补充缺失且无同级重名的预设，保留已有 ID、名称、层级、颜色与全部流水；仅在后续成功原子保存时记录标识。带该字段的文件不重新添加已删除分类。时间标签 JSON 版本 1 与事件 CSV 均不受影响。

新账本账户开账余额为零，直接允许记账。备注字段 `notes` 沿用既有格式，支持多行文字和单独修改（含转账、校准）；单独改备注保留金额、账户、日期和余额联动标志。

月统计按年和月匹配本地日历字段，年统计只按年份匹配。支出、收入分别汇总，转账和校准均排除；每层由父类直接账单、子类后代账单组成，显示金额、笔数和当前层总额占比，不重复计算。截图增加 `.test-artifacts/ledger-year-statistics.png` 和 `ledger-statistics-compact.png`，覆盖年度与 1100×740 布局。

## 日合计与录入事务

每日支出与收入仅按记录的本地日历日期和收支类型累计，显示在流水的日期分组标题中，录入侧栏不重复显示。合计覆盖所有已保存记录，不受流水分页或标签折叠影响。转账、校准不计入收支合计；旧版不联动余额的收支仍计入统计。修改日期、金额或类型，删除及撤销／重做后重新计算，持久化格式不增加汇总字段。

Enter、数字键盘 Enter、Ctrl+Enter 和保存按钮使用同一批量事务，包含所有已填支出、收入与备注，先完整验证再一次原子写入；失败保留全部输入。隐藏的无效字段会自动展开并获得焦点。中文输入法组词时保留 Enter 交互，左右键编辑光标，上下键在可见金额框间导航并自动滚动。输入框的原生撤销／重做动作连接到账单快照历史，未保存文字不随账单撤销被覆盖。
