# 记账存储与验收说明

记账使用独立的 `ledger.json`，共享数据目录及现有 `.daymark.lock`。时间记录的 `tags.json` 版本 1、CSV 六列及 UTF-8 BOM 保持不变。

## 版本 2

以下为合成示例，现金开账 10,000 元，已支付午餐 28 元。金额为整数分；日期是本地日历字段，无时区转换。

```json
{
  "version": 2,
  "default_cash_account_id": "cash",
  "balance_enabled": true,
  "accounts": [
    {"id": "cash", "name": "现金", "kind": "cash", "opening_cents": 1000000, "balance_cents": 997200},
    {"id": "provident", "name": "公积金", "kind": "provident", "opening_cents": 0, "balance_cents": 0},
    {"id": "investment", "name": "投资", "kind": "investment", "opening_cents": 0, "balance_cents": 0}
  ],
  "categories": [
    {"id": "food", "name": "餐饮", "kind": "expense", "parent_id": null},
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

当前起始分支只有时间记录，未提供既有记账实现或实际旧版记账样本。为升级路径定义并测试以下兼容契约；不读取或推测个人数据。

版本 1 使用上述 `accounts/categories/records/pinned` 列表，但账户只需 `id/name/kind/balance_cents`；收支只需 `id/kind/amount_cents/date/category_id`，备注可省略，没有余额影响信息。`default_cash_account_id` 可显式提供，缺省仅识别稳定 ID `cash`，不按名称或类型推断。

加载版本 1 时：

1. 每个账户现存余额作为暂存开账余额，所有历史收支保留并标记 `affects_balance: false`。原有账户关联保留，缺失关联补为显式默认现金 ID。
2. 不立即重写文件。用户填写所有账户当前实际余额后，启用联动并一次原子写入版本 2；首次启用作为新基线，不进入可撤销的录入历史。
3. 修改、删除旧收支不改变余额；新补记流水明确关联现金并影响余额。

该兼容契约针对没有自动余额联动的历史收支，不接受缺少明确账户关联的转账或校准；不支持猜测其他未提供的旧格式。版本 2 不会再次初始化或回放历史流水。

## 验收对应

`test/ledger_test.dart` 验证整数金额、10,000 → 9,972 → 10,972 元、收支类型修改、删除、批量、串行写入、撤销/重做、转账守恒、校准差额、多层分类移动汇总、默认账户关联、升级不重扣、跨月补记、失败回滚和损坏文件保护。

`test/ledger_widget_test.dart` 验证初始化失败保留输入、Enter 连续录入、Tab 金额框切换、Ctrl+Z/Y、批量写入、弹窗失败保留金额和备注、转账及校准、分类新增/移动/固定/顺序、月份与逐层占比、滚动自动扩展、模式切换及 1100×740 布局。截图使用合成记录和系统字体，输出到 `.test-artifacts/ledger.png`、`.test-artifacts/ledger-statistics.png`。

`tools/smoke_windows.ps1` 在不可激活的私有 Windows 桌面验证 Release 启动、窗口边界、时间 CSV 的 BOM/跨午夜空档、已联动记账文件不被回放改写、第二实例拒绝和退出释放共享锁。所有数据位于 `.test-artifacts/`。
