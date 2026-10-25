import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/ledger_store.dart';
import '../domain/history.dart';
import '../domain/ledger.dart';
import '../domain/model.dart';

class MoneyInput {
  const MoneyInput({
    required this.kind,
    required this.amountCents,
    required this.date,
    this.categoryId,
    this.notes = '',
    this.accountId,
  });
  final MoneyKind kind;
  final int amountCents;
  final DateTime date;
  final String? categoryId;
  final String notes;
  final String? accountId;
}

class LedgerController extends ChangeNotifier {
  LedgerController(this.store, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  final LedgerStore store;
  final DateTime Function() clock;
  final history = History<LedgerState>();
  LedgerState get state => store.state;
  Future<void> _tail = Future.value();
  bool _busy = false;
  bool get busy => _busy;
  Future<void> waitForWrites() => _tail;
  String _id() => const Uuid().v4();

  Future<T> _run<T>(Future<T> Function() action) {
    final result = _tail.then((_) async {
      _busy = true;
      notifyListeners();
      try {
        return await action();
      } finally {
        _busy = false;
        notifyListeners();
      }
    });
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<void> _apply(LedgerState desired, {bool record = true}) async {
    final before = state;
    await store.replace(desired);
    if (record) history.record(before, desired);
  }

  /// Recalculate from explicit linkage, so retries and edits never double apply.
  LedgerState _withRecords(Map<String, MoneyRecord> records) {
    final balances = {
      for (final account in state.accounts.values)
        account.id: account.openingCents,
    };
    for (final record in records.values) {
      for (final effect in record.balanceEffects.entries) {
        if (!balances.containsKey(effect.key)) {
          throw const FormatException('关联账户不存在。');
        }
        balances[effect.key] = balances[effect.key]! + effect.value;
      }
    }
    return state.copyWith(
      balanceEnabled: true,
      records: records,
      accounts: {
        for (final account in state.accounts.values)
          account.id: account.withBalance(balances[account.id]!),
      },
    );
  }

  Future<void> saveInputs(List<MoneyInput> inputs, {String? editId}) => _run(
    () async {
      if (inputs.isEmpty) return;
      final previous = editId == null ? null : state.records[editId];
      if (editId != null &&
          (previous == null ||
              inputs.length != 1 ||
              ![MoneyKind.expense, MoneyKind.income].contains(previous.kind))) {
        throw const FormatException('所编辑的收支不存在。');
      }
      final records = {...state.records};
      for (final input in inputs) {
        if (![MoneyKind.expense, MoneyKind.income].contains(input.kind)) {
          throw const FormatException('请使用转账或校准入口。');
        }
        final record = MoneyRecord(
          id: editId ?? _id(),
          kind: input.kind,
          amountCents: input.amountCents,
          date: dayStart(input.date),
          categoryId: input.categoryId,
          notes: input.notes.trim(),
          accountId:
              input.accountId ??
              previous?.accountId ??
              (input.kind == MoneyKind.income
                  ? state.incomeAccounts[input.categoryId]
                  : null) ??
              state.defaultCashId,
          affectsBalance: previous?.affectsBalance ?? true,
        );
        records[record.id] = record;
      }
      await _apply(_withRecords(records));
    },
  );

  Future<void> deleteRecord(String id) => _run(() async {
    if (!state.records.containsKey(id)) throw const FormatException('流水不存在。');
    await _apply(_withRecords({...state.records}..remove(id)));
  });

  Future<void> updateNotes(String id, String notes) => _run(() async {
    final previous = state.records[id];
    if (previous == null) throw const FormatException('流水不存在。');
    final record = MoneyRecord(
      id: previous.id,
      kind: previous.kind,
      amountCents: previous.amountCents,
      date: previous.date,
      categoryId: previous.categoryId,
      notes: notes.trim(),
      accountId: previous.accountId,
      toAccountId: previous.toAccountId,
      affectsBalance: previous.affectsBalance,
    );
    await _apply(state.copyWith(records: {...state.records, id: record}));
  });

  Future<void> transfer(
    String from,
    String to,
    int cents,
    DateTime date, {
    String notes = '',
    String? editId,
  }) => _run(() async {
    if (editId != null && state.records[editId]?.kind != MoneyKind.transfer) {
      throw const FormatException('所编辑的转账不存在。');
    }
    final record = MoneyRecord(
      id: editId ?? _id(),
      kind: MoneyKind.transfer,
      amountCents: cents,
      date: dayStart(date),
      accountId: from,
      toAccountId: to,
      notes: notes.trim(),
      affectsBalance: true,
    );
    await _apply(_withRecords({...state.records, record.id: record}));
  });

  Future<void> calibrate(
    String accountId,
    int actualCents,
    DateTime date, {
    String notes = '',
    String? editId,
  }) => _run(() async {
    if (editId != null && state.records[editId]?.kind != MoneyKind.adjustment) {
      throw const FormatException('所编辑的校准记录不存在。');
    }
    final baseline = editId == null
        ? state
        : _withRecords({...state.records}..remove(editId));
    final account = baseline.accounts[accountId];
    if (account == null || actualCents.abs() > maxMoneyCents) {
      throw const FormatException('账户或余额不正确。');
    }
    final delta = actualCents - account.balanceCents;
    if (delta == 0 && editId == null) {
      throw const FormatException('实际余额与账面余额一致，无需校准。');
    }
    final record = MoneyRecord(
      id: editId ?? _id(),
      kind: MoneyKind.adjustment,
      amountCents: delta,
      date: dayStart(date),
      accountId: accountId,
      notes: notes.trim(),
      affectsBalance: true,
    );
    await _apply(_withRecords({...state.records, record.id: record}));
  });

  Future<void> saveCategory(
    String name,
    MoneyKind kind,
    String? parentId, {
    String? id,
    CategoryColor? color,
    bool inheritColor = false,
    String? incomeAccountId,
    String? icon,
    bool inheritIcon = false,
  }) => _run(() async {
    final previous = id == null ? null : state.categories[id];
    if (id != null && (previous == null || previous.kind != kind)) {
      throw const FormatException('分类不存在或收支类型不同。');
    }
    final category = MoneyCategory(
      id ?? _id(),
      name.trim(),
      kind,
      parentId,
      inheritColor ? null : color ?? previous?.color,
      inheritIcon ? null : icon ?? previous?.icon,
    );
    final incomeAccounts = {...state.incomeAccounts};
    if (incomeAccountId != null) {
      if (kind != MoneyKind.income ||
          !state.accounts.containsKey(incomeAccountId)) {
        throw const FormatException('收入标签的入账账户不正确。');
      }
      if (incomeAccountId == state.defaultCashId) {
        incomeAccounts.remove(category.id);
      } else {
        incomeAccounts[category.id] = incomeAccountId;
      }
    }
    await _apply(
      state.copyWith(
        categories: {...state.categories, category.id: category},
        incomeAccounts: incomeAccounts,
      ),
    );
  });

  Future<void> deleteCategory(String id) => _run(() async {
    if (!state.categories.containsKey(id)) {
      throw const FormatException('分类不存在。');
    }
    if (state.categories.values.any((item) => item.parentId == id) ||
        state.records.values.any((item) => item.categoryId == id)) {
      throw const FormatException('请先移走子分类和关联流水。');
    }
    await _apply(
      state.copyWith(
        categories: {...state.categories}..remove(id),
        pinned: state.pinned.where((item) => item != id).toList(),
        categoryOrder: state.categoryOrder.where((item) => item != id).toList(),
        incomeAccounts: {...state.incomeAccounts}..remove(id),
      ),
    );
  });

  Future<void> setPinned(List<String> ids) =>
      _run(() => _apply(state.copyWith(pinned: ids)));

  /// Moves a branch and its sibling position in one undoable atomic write.
  Future<void> placeCategory(
    String id,
    String? parentId, {
    String? beforeId,
    String? afterId,
  }) => _run(() async {
    final source = state.categories[id];
    if (source == null || (beforeId != null && afterId != null)) {
      throw const FormatException('分类或目标位置不正确。');
    }
    if (parentId != null &&
        (state.categories[parentId]?.kind != source.kind ||
            state.descendants(id).contains(parentId))) {
      throw const FormatException('不能移到自己、子分类或其他收支类型中。');
    }
    final relativeId = beforeId ?? afterId;
    if (relativeId != null) {
      final relative = state.categories[relativeId];
      if (relative == null ||
          relative.id == id ||
          relative.kind != source.kind ||
          relative.parentId != parentId) {
        throw const FormatException('目标必须是同级分类。');
      }
    }
    final order = [
      ...state.orderedCategories(MoneyKind.expense).map((item) => item.id),
      ...state.orderedCategories(MoneyKind.income).map((item) => item.id),
    ]..remove(id);
    final siblings = state
        .categoryChildren(source.kind, parentId)
        .where((item) => item.id != id)
        .toList();
    final index = relativeId != null
        ? order.indexOf(relativeId) + (afterId != null ? 1 : 0)
        : siblings.isNotEmpty
        ? order.indexOf(siblings.last.id) + 1
        : parentId != null
        ? order.indexOf(parentId) + 1
        : order.length;
    order.insert(index, id);
    final moved = MoneyCategory(
      source.id,
      source.name,
      source.kind,
      parentId,
      source.color,
      source.icon,
    );
    await _apply(
      state.copyWith(
        categories: {...state.categories, id: moved},
        categoryOrder: order,
      ),
    );
  });

  Future<void> saveAccount(String name, {String? id}) => _run(() async {
    final previous = id == null ? null : state.accounts[id];
    if (id != null && previous == null) throw const FormatException('账户不存在。');
    final account =
        previous?.renamed(name) ??
        MoneyAccount(_id(), name.trim(), 'custom', 0, 0);
    await _apply(
      state.copyWith(accounts: {...state.accounts, account.id: account}),
    );
  });

  Future<void> deleteAccount(String id) => _run(() async {
    if (!state.accounts.containsKey(id)) throw const FormatException('账户不存在。');
    if (id == state.defaultCashId ||
        state.records.values.any(
          (item) => item.accountId == id || item.toAccountId == id,
        )) {
      throw const FormatException('默认现金账户或有关联流水的账户不能删除。');
    }
    if (state.accounts[id]!.balanceCents != 0) {
      throw const FormatException('请先转出账户余额。');
    }
    if (state.incomeAccounts.containsValue(id)) {
      throw const FormatException('请先修改收入标签绑定的入账账户。');
    }
    await _apply(state.copyWith(accounts: {...state.accounts}..remove(id)));
  });

  Future<bool> undo() =>
      _run(() => history.undo((snapshot) => _apply(snapshot, record: false)));
  Future<bool> redo() =>
      _run(() => history.redo((snapshot) => _apply(snapshot, record: false)));
}
