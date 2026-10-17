import 'dart:convert';
import 'dart:io';

import '../domain/ledger.dart';
import '../domain/model.dart';
import '../domain/unicode.dart';
import 'atomic_file.dart';
import 'store.dart';

class LedgerStore {
  LedgerStore._(this.directory, this._writer, this._state);
  final Directory directory;
  final FileWriter _writer;
  LedgerState _state;
  LedgerState get state => _state;
  File get file => File('${directory.path}/ledger.json');

  static Future<LedgerStore> open(
    Directory directory, {
    FileWriter writer = AtomicFile.write,
  }) async {
    await directory.create(recursive: true);
    final store = LedgerStore._(
      directory.absolute,
      writer,
      LedgerState.empty(),
    );
    if (await store.file.exists()) {
      try {
        store._state = decode(
          jsonDecode(
            (await store.file.readAsString()).replaceFirst(
              RegExp(r'^\uFEFF'),
              '',
            ),
          ),
        );
      } on FormatException catch (error) {
        throw DataError('无法读取 ${store.file.path}：${error.message}');
      }
    }
    // A missing ledger stays in memory until the first explicit money action.
    return store;
  }

  Future<void> replace(LedgerState desired) async {
    desired.validate();
    await _writer(
      file,
      utf8.encode(
        '${const JsonEncoder.withIndent('  ').convert(desired.toJson())}\n',
      ),
    );
    _state = desired;
  }

  static LedgerState decode(Object? source) {
    Map<String, Object?> object(Object? value) {
      if (value is! Map<String, Object?>) {
        throw const FormatException('记账对象格式不正确。');
      }
      return value;
    }

    String string(Map<String, Object?> row, String key) {
      final value = row[key];
      if (value is! String) throw FormatException('字段 $key 必须为文字。');
      return value;
    }

    String? optionalString(Map<String, Object?> row, String key) {
      final value = row[key];
      if (value != null && value is! String) {
        throw FormatException('字段 $key 必须为文字。');
      }
      return value as String?;
    }

    int integer(Map<String, Object?> row, String key) {
      final value = row[key];
      if (value is! int) throw FormatException('字段 $key 必须为整数分。');
      return value;
    }

    bool boolean(Map<String, Object?> row, String key) {
      final value = row[key];
      if (value is! bool) throw FormatException('字段 $key 必须为布尔值。');
      return value;
    }

    List<Object?> list(Map<String, Object?> row, String key) {
      final value = row[key];
      if (value is! List<Object?>) throw FormatException('字段 $key 必须为列表。');
      return value;
    }

    MoneyKind kind(Map<String, Object?> row) {
      final name = string(row, 'kind');
      return MoneyKind.values.firstWhere(
        (item) => item.name == name,
        orElse: () => throw const FormatException('流水类型不支持。'),
      );
    }

    final payload = object(source);
    final version = payload['version'];
    if (version != 1 && version != 2) {
      throw const FormatException('不支持的记账文件版本。');
    }
    final legacy = version == 1;
    final accounts = <String, MoneyAccount>{};
    for (final item in list(payload, 'accounts')) {
      final row = object(item);
      final id = string(row, 'id');
      if (accounts.containsKey(id)) throw const FormatException('账户 ID 重复。');
      final balance = integer(row, 'balance_cents');
      accounts[id] = MoneyAccount(
        id,
        string(row, 'name'),
        string(row, 'kind'),
        legacy ? balance : integer(row, 'opening_cents'),
        balance,
      );
    }
    final categories = <String, MoneyCategory>{};
    for (final item in list(payload, 'categories')) {
      final row = object(item);
      final id = string(row, 'id');
      if (categories.containsKey(id)) throw const FormatException('分类 ID 重复。');
      categories[id] = MoneyCategory(
        id,
        string(row, 'name'),
        kind(row),
        optionalString(row, 'parent_id'),
        optionalString(row, 'color') == null
            ? null
            : CategoryColor.values.firstWhere(
                (color) => color.name == row['color'],
                orElse: () => throw const FormatException('标签颜色不支持。'),
              ),
      );
    }
    // v1 had no automatic balance linkage. Never replay its historical entries.
    final defaultCash =
        optionalString(payload, 'default_cash_account_id') ??
        (legacy ? cashAccountId : throw const FormatException('缺少默认现金账户 ID。'));
    final records = <String, MoneyRecord>{};
    for (final item in list(payload, 'records')) {
      final row = object(item);
      final id = string(row, 'id');
      if (records.containsKey(id)) throw const FormatException('流水 ID 重复。');
      records[id] = MoneyRecord(
        id: id,
        kind: kind(row),
        amountCents: integer(row, 'amount_cents'),
        date: parseDate(string(row, 'date')),
        categoryId: optionalString(row, 'category_id'),
        notes: optionalString(row, 'notes') ?? '',
        accountId: legacy
            ? optionalString(row, 'account_id') ?? defaultCash
            : optionalString(row, 'account_id'),
        toAccountId: optionalString(row, 'to_account_id'),
        affectsBalance: legacy ? false : boolean(row, 'affects_balance'),
      );
    }
    final pins = list(payload, 'pinned');
    if (pins.any((item) => item is! String)) {
      throw const FormatException('常用分类 ID 格式不正确。');
    }
    final order = payload.containsKey('category_order')
        ? list(payload, 'category_order')
        : const <Object?>[];
    if (order.any((item) => item is! String)) {
      throw const FormatException('分类顺序 ID 格式不正确。');
    }
    final incomeAccounts = payload.containsKey('income_accounts')
        ? object(payload['income_accounts'])
        : const <String, Object?>{};
    if (incomeAccounts.values.any((value) => value is! String)) {
      throw const FormatException('收入标签的入账账户格式不正确。');
    }
    final state = LedgerState(
      accounts: accounts,
      categories: categories,
      records: records,
      defaultCashId: defaultCash,
      balanceEnabled: legacy ? false : boolean(payload, 'balance_enabled'),
      pinned: pins.cast<String>(),
      categoryOrder: order.cast<String>(),
      incomeAccounts: incomeAccounts.cast<String, String>(),
    );
    state.validate();
    final presets = payload['category_presets_version'];
    if (presets != null && presets != 1) {
      throw const FormatException('不支持的预设标签版本。');
    }
    if (presets != null) return state;
    // Upgrade defaults once, preserving customized names, IDs and associations.
    final upgraded = {...categories};
    for (final preset in defaultMoneyCategories) {
      final previous = upgraded[preset.id];
      if (previous != null) {
        upgraded[preset.id] = MoneyCategory(
          previous.id,
          previous.name,
          previous.kind,
          previous.parentId,
          previous.color ?? preset.color,
        );
      } else if ((preset.parentId == null ||
              upgraded[preset.parentId]?.kind == preset.kind) &&
          !upgraded.values.any(
            (item) =>
                item.kind == preset.kind &&
                item.parentId == preset.parentId &&
                caseFold(item.name.trim()) == caseFold(preset.name),
          )) {
        upgraded[preset.id] = preset;
      }
    }
    final migrated = state.copyWith(categories: upgraded);
    migrated.validate();
    return migrated;
  }
}
