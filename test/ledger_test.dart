import 'dart:convert';
import 'dart:io';

import 'package:daymark/application/ledger_controller.dart';
import 'package:daymark/data/atomic_file.dart';
import 'package:daymark/data/ledger_store.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late LedgerStore store;
  late LedgerController ledger;
  var fail = false;
  var writes = 0;
  final october = DateTime.utc(2026, 10, 11);
  final september = DateTime.utc(2026, 9, 30);
  final opening = {
    cashAccountId: 1000000,
    providentAccountId: 200000,
    investmentAccountId: 300000,
  };
  setUp(() async {
    directory = await (await Directory(
      '.test-artifacts',
    ).create()).createTemp('ledger-');
    fail = false;
    writes = 0;
    store = await LedgerStore.open(
      directory,
      writer: (file, bytes) async {
        writes++;
        if (fail) throw const FileSystemException('模拟保存失败');
        await AtomicFile.write(file, bytes);
      },
    );
    ledger = LedgerController(store);
    await store.replace(
      store.state.copyWith(
        accounts: {
          for (final account in store.state.accounts.values)
            account.id: MoneyAccount(
              account.id,
              account.name,
              account.kind,
              opening[account.id]!,
              opening[account.id]!,
            ),
        },
      ),
    );
  });
  tearDown(() async {
    ledger.dispose();
    await directory.delete(recursive: true);
  });
  int cash() => ledger.state.accounts[cashAccountId]!.balanceCents;
  MoneyInput expense(int amount, {String category = 'lunch', DateTime? date}) =>
      MoneyInput(
        kind: MoneyKind.expense,
        amountCents: amount,
        date: date ?? october,
        categoryId: category,
      );
  MoneyInput income(int amount) => MoneyInput(
    kind: MoneyKind.income,
    amountCents: amount,
    date: october,
    categoryId: 'salary',
  );

  test(
    'decimal money is exact and calendar dates reject rollover and zones',
    () {
      expect(parseMoney('28'), 2800);
      expect(parseMoney('0.29'), 29);
      expect(parseMoney('-1.01', signed: true), -101);
      expect(moneyText(-101), '-1.01');
      for (final invalid in [
        '1.001',
        'NaN',
        '1e3',
        '-1',
        '1,000',
        '999999999999999999',
      ]) {
        expect(() => parseMoney(invalid), throwsFormatException);
      }
      final source = ledger.state.toJson();
      source['records'] = [
        MoneyRecord(
          id: 'bad',
          kind: MoneyKind.expense,
          amountCents: 1,
          date: october,
          affectsBalance: false,
        ).toJson()..['date'] = '2026-02-30',
      ];
      expect(() => LedgerStore.decode(source), throwsFormatException);
    },
  );

  test(
    '10000 minus 28 plus 1000, editing kind, deletion, undo and redo',
    () async {
      await ledger.saveInputs([expense(2800)]);
      expect(cash(), 997200);
      final id = ledger.state.records.keys.single;
      await ledger.saveInputs([income(100000)]);
      expect(cash(), 1097200);
      await ledger.saveInputs([expense(3000)], editId: id);
      expect(cash(), 1097000);
      await ledger.saveInputs([income(3000)], editId: id);
      expect(cash(), 1103000);
      await ledger.deleteRecord(id);
      expect(cash(), 1100000);
      await ledger.undo();
      expect(cash(), 1103000);
      await ledger.undo();
      expect(cash(), 1097000);
      await ledger.redo();
      expect(cash(), 1103000);
      await ledger.redo();
      expect(cash(), 1100000);
      final reopened = (await LedgerStore.open(directory)).state;
      expect(reopened.accounts[cashAccountId]!.balanceCents, cash());
      expect(reopened.records.length, 1);
    },
  );

  test(
    'batch saves once, duplicates are independent, queue serializes transactions',
    () async {
      final previousWrites = writes;
      await ledger.saveInputs([expense(100), expense(200), expense(300)]);
      expect(writes, previousWrites + 1);
      expect(ledger.state.records.length, 3);
      expect(cash(), 999400);
      await ledger.undo();
      expect(cash(), 1000000);
      expect(ledger.state.records, isEmpty);
      await ledger.redo();
      expect(cash(), 999400);
      await Future.wait([
        ledger.saveInputs([expense(400)]),
        ledger.saveInputs([income(500)]),
      ]);
      expect(cash(), 999500);
    },
  );

  test(
    'transfer conserves assets, adjustment is a reversible delta, neither enters statistics',
    () async {
      final total = ledger.state.totalCents;
      await ledger.transfer(cashAccountId, investmentAccountId, 50000, october);
      expect(cash(), 950000);
      expect(ledger.state.accounts[investmentAccountId]!.balanceCents, 350000);
      expect(ledger.state.totalCents, total);
      await ledger.calibrate(investmentAccountId, 360000, october);
      expect(ledger.state.totalCents, total + 10000);
      expect(ledger.state.records.values.last.amountCents, 10000);
      expect(ledger.state.monthlyTotal(october, MoneyKind.expense), 0);
      expect(ledger.state.monthlyTotal(october, MoneyKind.income), 0);
      expect(ledger.state.expenseBreakdown(october), isEmpty);
      await ledger.undo();
      expect(ledger.state.accounts[investmentAccountId]!.balanceCents, 350000);
      await ledger.redo();
      expect(ledger.state.accounts[investmentAccountId]!.balanceCents, 360000);
      await ledger.deleteRecord(ledger.state.records.values.first.id);
      expect(cash(), 1000000);
      expect(ledger.state.accounts[investmentAccountId]!.balanceCents, 310000);
      await expectLater(
        ledger.transfer(cashAccountId, cashAccountId, 100, october),
        throwsFormatException,
      );
    },
  );

  test(
    'v1 balances and historical records survive migration without replay',
    () async {
      final legacy = LedgerState.empty().toJson()..['version'] = 1;
      legacy.remove('balance_enabled');
      legacy.remove('default_cash_account_id');
      legacy['accounts'] = [
        for (final account in LedgerState.empty().accounts.values)
          {
            'id': account.id,
            'name': account.name,
            'kind': account.kind,
            'balance_cents': opening[account.id],
          },
      ];
      legacy['records'] = [
        MoneyRecord(
            id: 'old',
            kind: MoneyKind.expense,
            amountCents: 2800,
            date: september,
            categoryId: 'lunch',
            affectsBalance: false,
          ).toJson()
          ..remove('affects_balance')
          ..remove('account_id'),
      ];
      await store.file.writeAsString(jsonEncode(legacy));
      ledger.dispose();
      store = await LedgerStore.open(directory);
      ledger = LedgerController(store);
      expect(cash(), 1000000);
      expect(ledger.state.balanceEnabled, isFalse);
      expect(ledger.state.records['old']!.affectsBalance, isFalse);
      await ledger.saveInputs([expense(5000, date: september)], editId: 'old');
      expect(cash(), 1000000);
      await ledger.saveInputs([income(8000)], editId: 'old');
      expect(cash(), 1000000);
      await ledger.deleteRecord('old');
      expect(cash(), 1000000);
      await ledger.undo();
      await ledger.saveInputs([expense(2800, date: september)]);
      expect(cash(), 997200);
      expect(ledger.state.monthlyTotal(september, MoneyKind.expense), 2800);
      expect(ledger.state.monthlyTotal(october, MoneyKind.expense), 0);
      final reopened = await LedgerStore.open(directory);
      expect(reopened.state.accounts[cashAccountId]!.balanceCents, 997200);
      expect(reopened.state.records['old']!.affectsBalance, isFalse);
      expect(
        jsonDecode(await store.file.readAsString()),
        containsPair('version', 2),
      );
    },
  );

  test(
    'stable categories survive moves and each expense enters exactly one bucket',
    () async {
      await ledger.saveCategory('工作日', MoneyKind.expense, 'lunch');
      final nested = ledger.state.categories.values
          .singleWhere((item) => item.name == '工作日')
          .id;
      await ledger.saveInputs([
        expense(1000, category: 'food'),
        expense(2000),
        expense(3000, category: nested),
        expense(4000, category: 'breakfast'),
        income(5000),
      ]);
      expect(ledger.state.monthlyTotal(october, MoneyKind.expense), 10000);
      var breakdown = ledger.state.expenseBreakdown(october, parentId: 'food');
      expect(
        breakdown.fold<int>(0, (sum, item) => sum + item.amountCents),
        10000,
      );
      expect(
        breakdown.singleWhere((item) => item.categoryId == 'lunch').amountCents,
        5000,
      );
      expect(breakdown.singleWhere((item) => item.direct).amountCents, 1000);
      expect(
        ledger.state
            .expenseBreakdown(october, parentId: 'lunch')
            .fold<int>(0, (sum, item) => sum + item.amountCents),
        5000,
      );
      await ledger.saveCategory(
        '工作日午餐',
        MoneyKind.expense,
        'transport',
        id: nested,
      );
      expect(
        ledger.state.records.values
            .singleWhere((item) => item.amountCents == 3000)
            .categoryId,
        nested,
      );
      breakdown = ledger.state.expenseBreakdown(october);
      expect(
        breakdown.fold<int>(0, (sum, item) => sum + item.amountCents),
        10000,
      );
      expect(
        breakdown.singleWhere((item) => item.categoryId == 'food').amountCents,
        7000,
      );
      await expectLater(
        ledger.saveCategory('交通', MoneyKind.expense, nested, id: 'transport'),
        throwsFormatException,
      );
      await expectLater(ledger.deleteCategory(nested), throwsFormatException);
      await ledger.setPinned([nested, 'lunch']);
      expect(ledger.state.pinned, [nested, 'lunch']);
      await ledger.undo();
      expect(ledger.state.pinned.first, 'breakfast');
    },
  );

  test(
    'account rename preserves explicit links and associated accounts cannot be deleted',
    () async {
      await ledger.saveInputs([expense(2800)]);
      await ledger.saveAccount('日常资金', id: cashAccountId);
      expect(ledger.state.defaultCashId, cashAccountId);
      expect(cash(), 997200);
      await ledger.saveAccount('储蓄');
      final added = ledger.state.accounts.values
          .singleWhere((item) => item.name == '储蓄')
          .id;
      await ledger.transfer(cashAccountId, added, 100, october);
      await ledger.transfer(added, cashAccountId, 100, october);
      await expectLater(ledger.deleteAccount(added), throwsFormatException);
      await expectLater(
        ledger.deleteAccount(cashAccountId),
        throwsFormatException,
      );
      await ledger.saveAccount('空账户');
      await ledger.deleteAccount(
        ledger.state.accounts.values
            .singleWhere((item) => item.name == '空账户')
            .id,
      );
      expect(
        ledger.state.accounts.values.any((item) => item.name == '空账户'),
        isFalse,
      );
    },
  );

  test(
    'failed batch, edit, transfer, adjustment and undo retain disk, state and history',
    () async {
      await ledger.saveInputs([expense(2800)]);
      final id = ledger.state.records.keys.single;
      final before = ledger.state;
      final bytes = await store.file.readAsBytes();
      fail = true;
      for (final operation in <Future<void> Function()>[
        () => ledger.saveInputs([expense(100), expense(200)]),
        () => ledger.saveInputs([income(1000)], editId: id),
        () => ledger.deleteRecord(id),
        () => ledger.transfer(cashAccountId, investmentAccountId, 100, october),
        () => ledger.calibrate(cashAccountId, 0, october),
        () async {
          await ledger.undo();
        },
      ]) {
        await expectLater(operation(), throwsA(isA<FileSystemException>()));
        expect(identical(ledger.state, before), isTrue);
        expect(await store.file.readAsBytes(), bytes);
        expect(ledger.history.canUndo, isTrue);
        expect(ledger.history.canRedo, isFalse);
      }
      fail = false;
      await ledger.undo();
      expect(cash(), 1000000);
      await ledger.redo();
      expect(cash(), 997200);
    },
  );

  test(
    'corrupt balance, duplicate IDs and unknown versions are protected',
    () async {
      for (final payload in [
        ledger.state.toJson()..['version'] = 99,
        ledger.state.toJson()
          ..['accounts'] = [
            ...ledger.state.accounts.values.map((item) => item.toJson()),
            ledger.state.accounts.values.first.toJson(),
          ],
        ledger.state.toJson()
          ..['accounts'] = [
            for (final item in ledger.state.accounts.values)
              item.toJson()..['balance_cents'] = 99,
          ],
      ]) {
        final source = jsonEncode(payload);
        await store.file.writeAsString(source);
        await expectLater(
          LedgerStore.open(directory),
          throwsA(isA<DataError>()),
        );
        expect(await store.file.readAsString(), source);
      }
    },
  );

  test(
    'new ledger starts at zero and first expense is atomic without setup',
    () async {
      await store.replace(LedgerState.empty());
      final bytes = await store.file.readAsBytes();
      fail = true;
      await expectLater(
        ledger.saveInputs([expense(1234)]),
        throwsA(isA<FileSystemException>()),
      );
      expect(cash(), 0);
      expect(await store.file.readAsBytes(), bytes);
      fail = false;
      await ledger.saveInputs([expense(1234)]);
      expect(cash(), -1234);
      expect((await LedgerStore.open(directory)).state.totalCents, -1234);
    },
  );

  test(
    'year statistics partition nested tags and exclude other years and movements',
    () async {
      await ledger.saveInputs([
        expense(1000, category: 'food', date: DateTime.utc(2026, 1, 1)),
        expense(2000, date: DateTime.utc(2026, 12, 31)),
        expense(3000, category: 'breakfast', date: DateTime.utc(2025, 12, 31)),
        MoneyInput(
          kind: MoneyKind.income,
          amountCents: 4000,
          date: DateTime.utc(2026, 1, 1),
          categoryId: 'salary',
        ),
        MoneyInput(
          kind: MoneyKind.income,
          amountCents: 5000,
          date: DateTime.utc(2026, 12, 31),
        ),
      ]);
      await ledger.transfer(cashAccountId, investmentAccountId, 6000, october);
      await ledger.calibrate(providentAccountId, 7000, october);
      final expenses = ledger.state.categoryBreakdown(
        october,
        LedgerPeriod.year,
        MoneyKind.expense,
        parentId: 'food',
      );
      expect(expenses.fold<int>(0, (sum, row) => sum + row.amountCents), 3000);
      expect(expenses.fold<int>(0, (sum, row) => sum + row.count), 2);
      expect(expenses.singleWhere((row) => row.direct).amountCents, 1000);
      expect(
        ledger.state.periodTotal(october, LedgerPeriod.year, MoneyKind.income),
        9000,
      );
      expect(
        ledger.state
            .categoryBreakdown(october, LedgerPeriod.year, MoneyKind.income)
            .singleWhere((row) => row.direct)
            .amountCents,
        5000,
      );
      expect(ledger.state.monthlyTotal(october, MoneyKind.expense), 0);
    },
  );

  test(
    'colors and multiline notes persist, moves retain colors and failed edits retain state',
    () async {
      await ledger.saveCategory(
        '午餐',
        MoneyKind.expense,
        'food',
        id: 'lunch',
        color: CategoryColor.pink,
      );
      await ledger.saveInputs([
        MoneyInput(
          kind: MoneyKind.expense,
          amountCents: 100,
          date: october,
          categoryId: 'lunch',
          notes: '第一行\n第二行',
        ),
      ]);
      final id = ledger.state.records.keys.single;
      await ledger.saveCategory('工作餐', MoneyKind.expense, null, id: 'lunch');
      expect(ledger.state.categories['lunch']!.color, CategoryColor.pink);
      final before = ledger.state;
      fail = true;
      await expectLater(
        ledger.saveInputs([
          MoneyInput(
            kind: MoneyKind.expense,
            amountCents: 100,
            date: october,
            notes: '修改备注',
          ),
        ], editId: id),
        throwsA(isA<FileSystemException>()),
      );
      expect(identical(ledger.state, before), isTrue);
      final reopened = (await LedgerStore.open(directory)).state;
      expect(reopened.records[id]!.notes, '第一行\n第二行');
      expect(reopened.categories['lunch']!.color, CategoryColor.pink);
      fail = false;
      await ledger.saveCategory(
        '工作餐',
        MoneyKind.expense,
        'food',
        id: 'lunch',
        inheritColor: true,
      );
      expect(ledger.state.categories['lunch']!.color, isNull);
    },
  );

  test(
    'old presets upgrade once without overwriting customization or recreating deleted defaults',
    () async {
      final source = ledger.state.toJson()..remove('category_presets_version');
      source['categories'] = [
        for (final category in ledger.state.categories.values.where(
          (item) => item.id != 'daily',
        ))
          category.toJson()..remove('color'),
      ];
      final upgraded = LedgerStore.decode(source);
      expect(upgraded.categories['daily']!.name, '日用');
      expect(upgraded.categories['food']!.color, CategoryColor.green);
      await store.replace(upgraded);
      await ledger.deleteCategory('daily');
      expect(
        (await LedgerStore.open(directory)).state.categories,
        isNot(contains('daily')),
      );
      final invalid = ledger.state.toJson();
      invalid['categories'] = [
        for (final category in ledger.state.categories.values)
          category.toJson()..['color'] = 'invalid',
      ];
      expect(() => LedgerStore.decode(invalid), throwsFormatException);
    },
  );
}
