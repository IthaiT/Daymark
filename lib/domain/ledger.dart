import 'model.dart';
import 'unicode.dart';

const cashAccountId = 'cash';
const providentAccountId = 'provident';
const investmentAccountId = 'investment';
const maxMoneyCents = 999999999999;

enum MoneyKind { expense, income, transfer, adjustment }

/// Decimal input is converted directly to cents, without floating point math.
int parseMoney(String text, {bool signed = false}) {
  final value = text.trim();
  if (!RegExp(
    signed ? r'^-?\d+(?:\.\d{1,2})?$' : r'^\d+(?:\.\d{1,2})?$',
  ).hasMatch(value)) {
    throw const FormatException('请输入金额，最多保留两位小数。');
  }
  final parts = value.replaceFirst('-', '').split('.');
  final whole = int.tryParse(parts.first);
  if (whole == null || whole > maxMoneyCents ~/ 100) {
    throw const FormatException('金额超出范围。');
  }
  final cents =
      whole * 100 +
      int.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
  if (cents > maxMoneyCents) throw const FormatException('金额超出范围。');
  return value.startsWith('-') ? -cents : cents;
}

String moneyText(int cents) =>
    '${cents < 0 ? '-' : ''}${cents.abs() ~/ 100}.${(cents.abs() % 100).toString().padLeft(2, '0')}';

class MoneyAccount {
  const MoneyAccount(
    this.id,
    this.name,
    this.kind,
    this.openingCents,
    this.balanceCents,
  );
  final String id;
  final String name;
  final String kind;
  final int openingCents;
  final int balanceCents;

  MoneyAccount withBalance(int value) =>
      MoneyAccount(id, name, kind, openingCents, value);
  MoneyAccount renamed(String value) =>
      MoneyAccount(id, value.trim(), kind, openingCents, balanceCents);
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind,
    'opening_cents': openingCents,
    'balance_cents': balanceCents,
  };
}

class MoneyCategory {
  const MoneyCategory(this.id, this.name, this.kind, [this.parentId]);
  final String id;
  final String name;
  final MoneyKind kind;
  final String? parentId;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'parent_id': parentId,
  };
}

class MoneyRecord {
  const MoneyRecord({
    required this.id,
    required this.kind,
    required this.amountCents,
    required this.date,
    this.categoryId,
    this.notes = '',
    this.accountId,
    this.toAccountId,
    required this.affectsBalance,
  });
  final String id;
  final MoneyKind kind;

  /// Positive for expense/income/transfer; signed delta for adjustment.
  final int amountCents;
  final DateTime date;
  final String? categoryId;
  final String notes;
  final String? accountId;
  final String? toAccountId;
  final bool affectsBalance;

  Map<String, int> get balanceEffects {
    if (!affectsBalance) return const {};
    return switch (kind) {
      MoneyKind.expense => {accountId!: -amountCents},
      MoneyKind.income || MoneyKind.adjustment => {accountId!: amountCents},
      MoneyKind.transfer => {
        accountId!: -amountCents,
        toAccountId!: amountCents,
      },
    };
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'amount_cents': amountCents,
    'date': dateText(date),
    'category_id': categoryId,
    'notes': notes,
    'account_id': accountId,
    'to_account_id': toAccountId,
    'affects_balance': affectsBalance,
  };
}

class CategoryAmount {
  const CategoryAmount(
    this.categoryId,
    this.amountCents, {
    this.direct = false,
  });
  final String? categoryId;
  final int amountCents;
  final bool direct;
}

/// A single immutable snapshot contains every balance and its linked records.
class LedgerState {
  LedgerState({
    required Map<String, MoneyAccount> accounts,
    required Map<String, MoneyCategory> categories,
    required Map<String, MoneyRecord> records,
    required this.defaultCashId,
    required this.balanceEnabled,
    required List<String> pinned,
  }) : accounts = Map.unmodifiable(accounts),
       categories = Map.unmodifiable(categories),
       records = Map.unmodifiable(records),
       pinned = List.unmodifiable(pinned);
  final Map<String, MoneyAccount> accounts;
  final Map<String, MoneyCategory> categories;
  final Map<String, MoneyRecord> records;
  final String defaultCashId;
  final bool balanceEnabled;
  final List<String> pinned;

  factory LedgerState.empty() {
    const categories = [
      MoneyCategory('food', '餐饮', MoneyKind.expense),
      MoneyCategory('breakfast', '早餐', MoneyKind.expense, 'food'),
      MoneyCategory('lunch', '午餐', MoneyKind.expense, 'food'),
      MoneyCategory('dinner', '晚餐', MoneyKind.expense, 'food'),
      MoneyCategory('other-food', '其他餐饮', MoneyKind.expense, 'food'),
      MoneyCategory('coffee', '咖啡', MoneyKind.expense, 'food'),
      MoneyCategory('transport', '交通', MoneyKind.expense),
      MoneyCategory('shopping', '购物', MoneyKind.expense),
      MoneyCategory('housing', '居住', MoneyKind.expense),
      MoneyCategory('health', '医疗', MoneyKind.expense),
      MoneyCategory('other-expense', '其他支出', MoneyKind.expense),
      MoneyCategory('salary', '工资', MoneyKind.income),
      MoneyCategory('bonus', '奖金', MoneyKind.income),
      MoneyCategory('other-income', '其他收入', MoneyKind.income),
    ];
    return LedgerState(
      accounts: const {
        cashAccountId: MoneyAccount(cashAccountId, '现金', 'cash', 0, 0),
        providentAccountId: MoneyAccount(
          providentAccountId,
          '公积金',
          'provident',
          0,
          0,
        ),
        investmentAccountId: MoneyAccount(
          investmentAccountId,
          '投资',
          'investment',
          0,
          0,
        ),
      },
      categories: {for (final category in categories) category.id: category},
      records: const {},
      defaultCashId: cashAccountId,
      balanceEnabled: false,
      pinned: const ['breakfast', 'lunch', 'dinner', 'coffee', 'transport'],
    );
  }

  LedgerState copyWith({
    Map<String, MoneyAccount>? accounts,
    Map<String, MoneyCategory>? categories,
    Map<String, MoneyRecord>? records,
    List<String>? pinned,
    bool? balanceEnabled,
  }) => LedgerState(
    accounts: accounts ?? this.accounts,
    categories: categories ?? this.categories,
    records: records ?? this.records,
    pinned: pinned ?? this.pinned,
    defaultCashId: defaultCashId,
    balanceEnabled: balanceEnabled ?? this.balanceEnabled,
  );

  int get totalCents =>
      accounts.values.fold(0, (sum, account) => sum + account.balanceCents);

  Set<String> descendants(String id) {
    final result = <String>{id};
    final pending = [id];
    while (pending.isNotEmpty) {
      final parent = pending.removeLast();
      for (final category in categories.values.where(
        (item) => item.parentId == parent,
      )) {
        if (result.add(category.id)) pending.add(category.id);
      }
    }
    return result;
  }

  List<MoneyCategory> ancestors(String id) {
    final result = <MoneyCategory>[];
    String? cursor = id;
    while (cursor != null) {
      final category = categories[cursor]!;
      result.add(category);
      cursor = category.parentId;
    }
    return result.reversed.toList();
  }

  String categoryPath(String? id) =>
      id == null ? '未分类' : ancestors(id).map((item) => item.name).join(' / ');

  List<MoneyCategory> orderedCategories(MoneyKind kind) {
    final result = <MoneyCategory>[];
    void visit(String? parent) {
      final children =
          categories.values
              .where((item) => item.kind == kind && item.parentId == parent)
              .toList()
            ..sort(
              (a, b) => compareUnicode(caseFold(a.name), caseFold(b.name)),
            );
      for (final child in children) {
        result.add(child);
        visit(child.id);
      }
    }

    visit(null);
    return result;
  }

  List<MoneyRecord> monthRecords(DateTime month) => records.values
      .where(
        (record) =>
            record.date.year == month.year && record.date.month == month.month,
      )
      .toList();
  int monthlyTotal(DateTime month, MoneyKind kind) => monthRecords(month)
      .where((record) => record.kind == kind)
      .fold(0, (sum, record) => sum + record.amountCents);

  /// Direct parent spending is a separate bucket; children partition descendants.
  List<CategoryAmount> expenseBreakdown(DateTime month, {String? parentId}) {
    final expenses = monthRecords(
      month,
    ).where((record) => record.kind == MoneyKind.expense).toList();
    final children = categories.values.where(
      (item) => item.kind == MoneyKind.expense && item.parentId == parentId,
    );
    final result = <CategoryAmount>[
      CategoryAmount(
        parentId,
        expenses
            .where((record) => record.categoryId == parentId)
            .fold(0, (sum, record) => sum + record.amountCents),
        direct: true,
      ),
    ]..removeWhere((item) => item.amountCents == 0);
    for (final child in children) {
      final ids = descendants(child.id);
      final amount = expenses
          .where((record) => ids.contains(record.categoryId))
          .fold<int>(0, (sum, record) => sum + record.amountCents);
      if (amount > 0) result.add(CategoryAmount(child.id, amount));
    }
    result.sort((a, b) => b.amountCents.compareTo(a.amountCents));
    return result;
  }

  List<MoneyRecord> recordsThrough(DateTime month) {
    final order = {for (final (index, id) in records.keys.indexed) id: index};
    return records.values
        .where(
          (record) =>
              record.date.isBefore(DateTime.utc(month.year, month.month + 1)),
        )
        .toList()
      ..sort((a, b) {
        final date = b.date.compareTo(a.date);
        return date == 0 ? order[b.id]!.compareTo(order[a.id]!) : date;
      });
  }

  void validate() {
    if (!accounts.containsKey(defaultCashId)) {
      throw const FormatException('默认现金账户不存在。');
    }
    for (final entry in accounts.entries) {
      final account = entry.value;
      if (entry.key != account.id ||
          account.id.isEmpty ||
          account.name.trim().isEmpty ||
          account.kind.isEmpty ||
          account.openingCents.abs() > maxMoneyCents ||
          account.balanceCents.abs() > maxMoneyCents) {
        throw const FormatException('账户数据不正确。');
      }
    }
    final siblings = <(String?, MoneyKind, String)>{};
    for (final entry in categories.entries) {
      final category = entry.value;
      if (entry.key != category.id ||
          category.id.isEmpty ||
          category.name.trim().isEmpty ||
          ![MoneyKind.expense, MoneyKind.income].contains(category.kind)) {
        throw const FormatException('分类数据不正确。');
      }
      if (!siblings.add((
        category.parentId,
        category.kind,
        caseFold(category.name.trim()),
      ))) {
        throw const FormatException('同级分类不能重名。');
      }
      final visited = <String>{category.id};
      var parent = category.parentId;
      while (parent != null) {
        if (!visited.add(parent)) {
          throw const FormatException('不能移到自己或自己的子分类中。');
        }
        final ancestor = categories[parent];
        if (ancestor == null || ancestor.kind != category.kind) {
          throw const FormatException('父分类不存在或收支类型不同。');
        }
        parent = ancestor.parentId;
      }
    }
    if (pinned.toSet().length != pinned.length ||
        pinned.any((id) => categories[id]?.kind != MoneyKind.expense)) {
      throw const FormatException('常用分类数据不正确。');
    }
    final expected = {
      for (final account in accounts.values) account.id: account.openingCents,
    };
    for (final entry in records.entries) {
      final record = entry.value;
      if (entry.key != record.id ||
          record.id.isEmpty ||
          record.amountCents.abs() > maxMoneyCents ||
          record.date.year < 1 ||
          record.date.year > 9999 ||
          record.date != dayStart(record.date)) {
        throw const FormatException('流水数据不正确。');
      }
      if (record.kind != MoneyKind.adjustment && record.amountCents <= 0) {
        throw const FormatException('收支和转账金额必须大于零。');
      }
      if (record.categoryId != null &&
          categories[record.categoryId]?.kind != record.kind) {
        throw const FormatException('流水分类不存在或收支类型不同。');
      }
      if (record.accountId != null && !accounts.containsKey(record.accountId)) {
        throw const FormatException('流水账户不存在。');
      }
      if (record.affectsBalance &&
          (!balanceEnabled || record.accountId == null)) {
        throw const FormatException('余额关联信息不完整。');
      }
      switch (record.kind) {
        case MoneyKind.expense || MoneyKind.income:
          if (record.toAccountId != null) {
            throw const FormatException('收支不能包含转入账户。');
          }
        case MoneyKind.transfer:
          if (!record.affectsBalance ||
              record.categoryId != null ||
              !accounts.containsKey(record.toAccountId) ||
              record.toAccountId == record.accountId) {
            throw const FormatException('转账账户不正确。');
          }
        case MoneyKind.adjustment:
          if (!record.affectsBalance ||
              record.categoryId != null ||
              record.toAccountId != null) {
            throw const FormatException('校准记录不正确。');
          }
      }
      for (final effect in record.balanceEffects.entries) {
        expected[effect.key] = expected[effect.key]! + effect.value;
      }
    }
    if (accounts.values.any(
      (account) => expected[account.id] != account.balanceCents,
    )) {
      throw const FormatException('账户余额与关联流水不一致，原文件已保留。');
    }
  }

  Map<String, Object?> toJson() => {
    'version': 2,
    'default_cash_account_id': defaultCashId,
    'balance_enabled': balanceEnabled,
    'accounts': accounts.values.map((item) => item.toJson()).toList(),
    'categories': categories.values.map((item) => item.toJson()).toList(),
    'records': records.values.map((item) => item.toJson()).toList(),
    'pinned': pinned,
  };
}
