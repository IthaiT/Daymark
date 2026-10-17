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
    'income accounts persist and edits reverse the previous account effect',
    () async {
      MoneyInput linked(int amount, String account) => MoneyInput(
        kind: MoneyKind.income,
        amountCents: amount,
        date: october,
        categoryId: 'salary',
        accountId: account,
      );
      await ledger.saveInputs([
        linked(10000, providentAccountId),
        income(5000),
      ]);
      final id = ledger.state.records.values.first.id;
      expect(cash(), 1005000);
      expect(ledger.state.accounts[providentAccountId]!.balanceCents, 210000);
      final before = ledger.state;
      final bytes = await store.file.readAsBytes();
      fail = true;
      await expectLater(
        ledger.saveInputs([linked(15000, investmentAccountId)], editId: id),
        throwsA(isA<FileSystemException>()),
      );
      expect(ledger.state, same(before));
      expect(await store.file.readAsBytes(), bytes);
      fail = false;
      await ledger.saveInputs([linked(15000, investmentAccountId)], editId: id);
      expect(ledger.state.accounts[providentAccountId]!.balanceCents, 200000);
      expect(ledger.state.accounts[investmentAccountId]!.balanceCents, 315000);
      final reopened = (await LedgerStore.open(directory)).state;
      expect(reopened.records[id]!.accountId, investmentAccountId);
      expect(reopened.accounts[investmentAccountId]!.balanceCents, 315000);
      await ledger.undo();
      expect(ledger.state.records[id]!.accountId, providentAccountId);
      await ledger.redo();
      expect(ledger.state.records[id]!.accountId, investmentAccountId);
      final valid = ledger.state;
      await expectLater(
        ledger.saveInputs([linked(100, 'missing')]),
        throwsFormatException,
      );
      expect(ledger.state, same(valid));
    },
  );

  test(
    'movement edits replace one record atomically and preserve later flows',
    () async {
      await ledger.transfer(cashAccountId, investmentAccountId, 50000, october);
      final transferId = ledger.state.records.keys.single;
      await ledger.calibrate(providentAccountId, 210000, october);
      final adjustmentId = ledger.state.records.keys.last;
      await ledger.saveInputs([expense(1000)]);
      final before = ledger.state;
      final bytes = await store.file.readAsBytes();
      fail = true;
      for (final action in <Future<void> Function()>[
        () => ledger.transfer(
          providentAccountId,
          cashAccountId,
          20000,
          september,
          editId: transferId,
          notes: '修改转账',
        ),
        () => ledger.calibrate(
          investmentAccountId,
          295000,
          september,
          editId: adjustmentId,
        ),
      ]) {
        await expectLater(action(), throwsA(isA<FileSystemException>()));
        expect(ledger.state, same(before));
        expect(await store.file.readAsBytes(), bytes);
      }
      fail = false;
      await ledger.transfer(
        providentAccountId,
        cashAccountId,
        20000,
        september,
        editId: transferId,
        notes: '修改转账',
      );
      expect(cash(), 1019000);
      expect(ledger.state.accounts[investmentAccountId]!.balanceCents, 300000);
      expect(ledger.state.accounts[providentAccountId]!.balanceCents, 190000);
      expect(ledger.state.records.length, 3);
      expect(ledger.state.records[transferId]!.date, september);
      expect(ledger.state.records[transferId]!.notes, '修改转账');
      final afterTransfer = ledger.state;
      await ledger.calibrate(
        investmentAccountId,
        295000,
        september,
        editId: adjustmentId,
        notes: '更正差额',
      );
      expect(cash(), 1019000);
      expect(ledger.state.accounts[providentAccountId]!.balanceCents, 180000);
      expect(ledger.state.accounts[investmentAccountId]!.balanceCents, 295000);
      expect(ledger.state.records.length, 3);
      final reopened = (await LedgerStore.open(directory)).state;
      expect(reopened.toJson(), ledger.state.toJson());
      await ledger.undo();
      expect(ledger.state.toJson(), afterTransfer.toJson());
      await ledger.undo();
      expect(ledger.state.toJson(), before.toJson());
      await ledger.redo();
      await ledger.redo();
      expect(ledger.state.toJson(), reopened.toJson());
      final valid = ledger.state;
      for (final action in <Future<void> Function()>[
        () => ledger.transfer(
          cashAccountId,
          cashAccountId,
          100,
          october,
          editId: transferId,
        ),
        () => ledger.transfer(
          cashAccountId,
          providentAccountId,
          0,
          october,
          editId: transferId,
        ),
        () => ledger.transfer(
          cashAccountId,
          providentAccountId,
          100,
          october,
          editId: adjustmentId,
        ),
        () => ledger.calibrate(cashAccountId, 100, october, editId: transferId),
        () => ledger.calibrate('missing', 100, october, editId: adjustmentId),
      ]) {
        await expectLater(action(), throwsFormatException);
        expect(ledger.state, same(valid));
      }
    },
  );

  test(
    'category filters cover descendants, unclassified, periods and direct entries',
    () async {
      await ledger.saveInputs([
        expense(1000, category: 'food'),
        expense(2000),
        expense(3000, category: 'breakfast'),
        expense(4000, category: 'transport'),
        MoneyInput(kind: MoneyKind.expense, amountCents: 500, date: october),
        expense(100, category: 'transport', date: september),
        income(20000),
      ]);
      await ledger.transfer(
        cashAccountId,
        investmentAccountId,
        700000,
        october,
      );
      List<CategoryAmount> rows({
        String? parent,
        Set<String?>? include,
        Set<String?> exclude = const {},
        LedgerPeriod period = LedgerPeriod.month,
      }) => ledger.state.categoryBreakdown(
        october,
        period,
        MoneyKind.expense,
        parentId: parent,
        includedCategoryIds: include,
        excludedCategoryIds: exclude,
      );
      int sum(List<CategoryAmount> values) =>
          values.fold(0, (sum, row) => sum + row.amountCents);
      expect(sum(rows(exclude: {'transport'})), 6500);
      expect(sum(rows(exclude: {'food'})), 4500);
      expect(sum(rows(include: {'food', 'lunch'})), 6000);
      expect(sum(rows(include: {'food'}, exclude: {'lunch'})), 4000);
      expect(
        sum(rows(parent: 'food', include: {'food'}, exclude: {'lunch'})),
        4000,
      );
      expect(rows(parent: 'food', exclude: {'food'}), isEmpty);
      expect(rows(include: {}), isEmpty);
      expect(sum(rows(include: {null})), 500);
      expect(sum(rows(exclude: {null})), 10000);
      expect(
        sum(rows(include: {'transport'}, period: LedgerPeriod.year)),
        4100,
      );
      expect(
        rows(
          exclude: {'transport'},
        ).fold<int>(0, (sum, row) => sum + row.count),
        4,
      );
      expect(ledger.state.monthlyTotal(october, MoneyKind.expense), 10500);
    },
  );

  test(
    'calibration edits undo the old effect before targeting the actual balance',
    () async {
      await ledger.calibrate(investmentAccountId, 400000, october);
      final id = ledger.state.records.keys.single;
      await ledger.transfer(investmentAccountId, cashAccountId, 20000, october);
      final before = ledger.state;
      final bytes = await store.file.readAsBytes();
      fail = true;
      await expectLater(
        ledger.calibrate(
          investmentAccountId,
          350000,
          september,
          editId: id,
          notes: '更正余额',
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(ledger.state, same(before));
      expect(await store.file.readAsBytes(), bytes);
      fail = false;
      await ledger.calibrate(
        investmentAccountId,
        350000,
        september,
        editId: id,
        notes: '更正余额',
      );
      expect(ledger.state.accounts[investmentAccountId]!.balanceCents, 350000);
      expect(ledger.state.records[id]!.amountCents, 70000);
      expect(ledger.state.records[id]!.date, september);
      expect(ledger.state.records.length, 2);
      expect(cash(), 1020000);
      final updated = ledger.state;
      expect(
        (await LedgerStore.open(directory)).state.toJson(),
        updated.toJson(),
      );
      await ledger.undo();
      expect(ledger.state.toJson(), before.toJson());
      await ledger.redo();
      expect(ledger.state.toJson(), updated.toJson());
      await ledger.calibrate(providentAccountId, 220000, october, editId: id);
      expect(ledger.state.accounts[investmentAccountId]!.balanceCents, 280000);
      expect(ledger.state.accounts[providentAccountId]!.balanceCents, 220000);
      expect(ledger.state.records[id]!.amountCents, 20000);
      await ledger.calibrate(providentAccountId, 200000, october, editId: id);
      expect(ledger.state.records[id]!.amountCents, 0);
      expect(ledger.state.accounts[providentAccountId]!.balanceCents, 200000);
      final valid = ledger.state;
      await expectLater(
        ledger.calibrate(cashAccountId, 0, october, editId: 'missing'),
        throwsFormatException,
      );
      await expectLater(
        ledger.calibrate('missing', 0, october, editId: id),
        throwsFormatException,
      );
      expect(ledger.state, same(valid));
    },
  );

  test(
    'income category accounts persist and only apply to new records',
    () async {
      await ledger.saveCategory(
        '工资',
        MoneyKind.income,
        null,
        id: 'salary',
        incomeAccountId: providentAccountId,
      );
      expect((await LedgerStore.open(directory)).state.incomeAccounts, {
        'salary': providentAccountId,
      });
      await ledger.saveInputs([income(10000)]);
      final id = ledger.state.records.keys.single;
      expect(ledger.state.records[id]!.accountId, providentAccountId);
      await ledger.saveCategory(
        '工资',
        MoneyKind.income,
        null,
        id: 'salary',
        incomeAccountId: investmentAccountId,
      );
      await ledger.saveInputs([income(12000)], editId: id);
      expect(ledger.state.records[id]!.accountId, providentAccountId);
      await ledger.saveInputs([income(2000)]);
      expect(ledger.state.records.values.last.accountId, investmentAccountId);
      expect(cash(), 1000000);
      await ledger.saveCategory('工资改名', MoneyKind.income, null, id: 'salary');
      await ledger.placeCategory('salary', 'bonus');
      expect(ledger.state.incomeAccounts['salary'], investmentAccountId);
      final before = ledger.state;
      final bytes = await store.file.readAsBytes();
      fail = true;
      await expectLater(
        ledger.saveCategory(
          '工资改名',
          MoneyKind.income,
          'bonus',
          id: 'salary',
          incomeAccountId: cashAccountId,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(ledger.state, same(before));
      expect(await store.file.readAsBytes(), bytes);
      fail = false;
      await ledger.saveCategory(
        '工资改名',
        MoneyKind.income,
        'bonus',
        id: 'salary',
        incomeAccountId: cashAccountId,
      );
      expect(ledger.state.incomeAccounts, isEmpty);
      await ledger.undo();
      expect(ledger.state.incomeAccounts['salary'], investmentAccountId);
      await ledger.redo();
      expect(ledger.state.incomeAccounts, isEmpty);
      final legacy = ledger.state.toJson()..remove('income_accounts');
      expect(LedgerStore.decode(legacy).incomeAccounts, isEmpty);
      for (final invalid in <Object?>[
        null,
        [],
        {'salary': 123},
        {'missing': cashAccountId},
        {'lunch': cashAccountId},
        {'salary': 'missing'},
      ]) {
        expect(
          () => LedgerStore.decode({...legacy, 'income_accounts': invalid}),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'category account links protect accounts and are removed with the category',
    () async {
      await ledger.saveAccount('未使用账户');
      final account = ledger.state.accounts.keys.last;
      await ledger.saveCategory(
        '专项收入',
        MoneyKind.income,
        null,
        incomeAccountId: account,
      );
      final category = ledger.state.categories.keys.last;
      await expectLater(ledger.deleteAccount(account), throwsFormatException);
      await expectLater(
        ledger.saveCategory(
          '专项收入',
          MoneyKind.income,
          null,
          id: category,
          incomeAccountId: 'missing',
        ),
        throwsFormatException,
      );
      await expectLater(
        ledger.saveCategory(
          '午餐',
          MoneyKind.expense,
          'food',
          id: 'lunch',
          incomeAccountId: account,
        ),
        throwsFormatException,
      );
      await ledger.deleteCategory(category);
      expect(ledger.state.incomeAccounts, isEmpty);
      await ledger.deleteAccount(account);
      expect(ledger.state.accounts.containsKey(account), isFalse);
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
  test(
    'transfer and calibration notes are atomic and reversible without balance effects',
    () async {
      await ledger.transfer(
        cashAccountId,
        investmentAccountId,
        1000,
        october,
        notes: '转入储蓄',
      );
      await ledger.calibrate(providentAccountId, 200100, october, notes: '对账');
      for (final record in ledger.state.records.values.toList()) {
        final balances = ledger.state.accounts.map(
          (id, account) => MapEntry(id, account.balanceCents),
        );
        final before = ledger.state;
        fail = true;
        await expectLater(
          ledger.updateNotes(record.id, '新备注\n第二行'),
          throwsA(isA<FileSystemException>()),
        );
        expect(identical(ledger.state, before), isTrue);
        fail = false;
        await ledger.updateNotes(record.id, '新备注\n第二行');
        expect(
          ledger.state.accounts.map(
            (id, account) => MapEntry(id, account.balanceCents),
          ),
          balances,
        );
        expect(
          (await LedgerStore.open(directory)).state.records[record.id]!.notes,
          '新备注\n第二行',
        );
        await ledger.undo();
        expect(ledger.state.records[record.id]!.notes, record.notes);
        await ledger.redo();
        expect(ledger.state.records[record.id]!.notes, '新备注\n第二行');
      }
    },
  );

  test(
    'requested preset categories are complete and old custom IDs win name conflicts',
    () {
      final state = LedgerState.empty();
      expect(
        state.categories.values
            .where(
              (item) => item.kind == MoneyKind.expense && item.parentId == null,
            )
            .map((item) => item.name),
        [
          '餐饮',
          '住房',
          '日用',
          '交通',
          '服饰',
          '爱好',
          '医疗',
          '充值',
          '消费',
          '购物',
          '娱乐',
          '缴费',
          '其他',
        ],
      );
      final source = state.toJson()..remove('category_presets_version');
      source['pinned'] = <String>[];
      source['categories'] = [
        const MoneyCategory('custom-daily', '日用', MoneyKind.expense).toJson(),
        const MoneyCategory('food', '自定义收入', MoneyKind.income).toJson(),
      ];
      final migrated = LedgerStore.decode(source);
      expect(migrated.categories, contains('custom-daily'));
      expect(migrated.categories, isNot(contains('daily')));
      expect(migrated.categories, isNot(contains('lunch')));
      expect(migrated.categories['food']!.name, '自定义收入');
    },
  );
  test(
    'daily totals preserve calendar days and update with edit, delete, undo and redo',
    () async {
      await ledger.saveInputs([
        expense(2800, date: DateTime(2026, 10, 11, 23, 59)),
        expense(500, date: september),
        MoneyInput(
          kind: MoneyKind.income,
          amountCents: 10000,
          date: october,
          categoryId: 'salary',
        ),
      ]);
      final id = ledger.state.records.values.first.id;
      await ledger.transfer(cashAccountId, investmentAccountId, 50000, october);
      await ledger.calibrate(
        providentAccountId,
        190000,
        DateTime.utc(2026, 10, 12),
      );
      expect(ledger.state.dailyTotals[october], (
        expenseCents: 2800,
        incomeCents: 10000,
      ));
      expect(ledger.state.dailyTotals[september], (
        expenseCents: 500,
        incomeCents: 0,
      ));
      expect(ledger.state.dailyTotals[DateTime.utc(2026, 10, 12)], (
        expenseCents: 0,
        incomeCents: 0,
      ));
      expect(() => ledger.state.dailyTotals.clear(), throwsUnsupportedError);
      await ledger.saveInputs([expense(2900, date: september)], editId: id);
      expect(ledger.state.dailyTotals[october]!.expenseCents, 0);
      expect(ledger.state.dailyTotals[september]!.expenseCents, 3400);
      final before = ledger.state.dailyTotals;
      fail = true;
      await expectLater(
        ledger.deleteRecord(id),
        throwsA(isA<FileSystemException>()),
      );
      expect(ledger.state.dailyTotals, before);
      fail = false;
      await ledger.deleteRecord(id);
      expect(ledger.state.dailyTotals[september]!.expenseCents, 500);
      await ledger.undo();
      expect(ledger.state.dailyTotals[september]!.expenseCents, 3400);
      await ledger.redo();
      expect(ledger.state.dailyTotals[september]!.expenseCents, 500);
    },
  );
  test(
    'category ordering moves whole root branches and siblings, persists and supports undo',
    () async {
      await ledger.saveInputs([expense(2800)]);
      await ledger.placeCategory('transport', null, beforeId: 'food');
      expect(
        store.state.categoryChildren(MoneyKind.expense, null).first.id,
        'transport',
      );
      await ledger.placeCategory('lunch', 'food', beforeId: 'breakfast');
      expect(
        store.state.categoryChildren(MoneyKind.expense, 'food').first.id,
        'lunch',
      );
      expect(store.state.records.values.single.categoryId, 'lunch');
      final reopened = await LedgerStore.open(directory);
      expect(reopened.state.categoryOrder, store.state.categoryOrder);
      await ledger.undo();
      expect(
        store.state.categoryChildren(MoneyKind.expense, 'food').first.id,
        'breakfast',
      );
      await ledger.redo();
      expect(
        store.state.categoryChildren(MoneyKind.expense, 'food').first.id,
        'lunch',
      );
      await ledger.placeCategory('food', null, afterId: 'housing');
      expect(store.state.categories['lunch']!.parentId, 'food');
      expect(
        store.state
            .categoryChildren(MoneyKind.expense, null)
            .map((item) => item.id)
            .toList()
            .indexOf('food'),
        greaterThan(
          store.state
              .categoryChildren(MoneyKind.expense, null)
              .map((item) => item.id)
              .toList()
              .indexOf('housing'),
        ),
      );
    },
  );

  test('dragging a category keeps its icon, colour and parent move', () async {
    await ledger.saveCategory(
      '咖啡',
      MoneyKind.expense,
      'food',
      icon: 'local_cafe',
      color: CategoryColor.pink,
    );
    final id = store.state.categories.values
        .singleWhere((item) => item.name == '咖啡')
        .id;
    await ledger.placeCategory(id, 'food', beforeId: 'breakfast');
    expect(store.state.categories[id]!.icon, 'local_cafe');
    expect(store.state.categories[id]!.color, CategoryColor.pink);
    await ledger.placeCategory(id, 'food', afterId: 'other-food');
    expect(store.state.categories[id]!.icon, 'local_cafe');
    await ledger.placeCategory(id, null);
    expect(store.state.categories[id]!.icon, 'local_cafe');
    expect(store.state.categories[id]!.parentId, isNull);
  });

  test(
    'ordering rejects cycles and foreign kinds and rolls back failed writes',
    () async {
      final before = store.state.toJson();
      for (final action in [
        () => ledger.placeCategory('food', 'lunch'),
        () => ledger.placeCategory('salary', 'food'),
        () => ledger.placeCategory('lunch', 'food', beforeId: 'housing'),
        () => ledger.placeCategory('food', null, beforeId: 'food'),
      ]) {
        await expectLater(action(), throwsFormatException);
        expect(store.state.toJson(), before);
      }
      fail = true;
      await expectLater(
        ledger.placeCategory('transport', null, beforeId: 'food'),
        throwsA(isA<FileSystemException>()),
      );
      expect(store.state.toJson(), before);
      fail = false;
      await ledger.placeCategory('transport', null, beforeId: 'food');
      expect(store.state.categoryOrder.first, 'transport');
      await expectLater(
        () => store.state.categoryOrder.clear(),
        throwsUnsupportedError,
      );
    },
  );
  test(
    'optional category order reads legacy files and rejects corrupt IDs without overwriting',
    () async {
      final payload = store.state.toJson()..remove('category_order');
      await store.file.writeAsString(jsonEncode(payload));
      final legacy = await LedgerStore.open(directory);
      expect(legacy.state.categoryOrder, isEmpty);
      expect(legacy.state.pinned, store.state.pinned);
      for (final order in [
        ['food', 'food'],
        ['missing'],
        [42],
      ]) {
        payload['category_order'] = order;
        final content = jsonEncode(payload);
        await store.file.writeAsString(content);
        await expectLater(
          LedgerStore.open(directory),
          throwsA(isA<DataError>()),
        );
        expect(await store.file.readAsString(), content);
      }
    },
  );
  test('category icons round trip, clear and survive unknown names', () async {
    await ledger.saveCategory(
      '咖啡',
      MoneyKind.expense,
      'food',
      icon: 'local_cafe',
    );
    final coffee = store.state.categories.values.singleWhere(
      (item) => item.name == '咖啡',
    );
    expect(coffee.icon, 'local_cafe');
    final saved =
        jsonDecode(await store.file.readAsString()) as Map<String, Object?>;
    expect(saved['categories'], contains(containsPair('icon', 'local_cafe')));
    final reopened = LedgerStore.decode(
      jsonDecode(await store.file.readAsString()),
    );
    expect(reopened.categories[coffee.id]!.icon, 'local_cafe');

    // A newer icon name must not make the whole ledger unreadable.
    final payload =
        jsonDecode(await store.file.readAsString()) as Map<String, Object?>;
    final rows = (payload['categories']! as List<Object?>)
        .cast<Map<String, Object?>>();
    rows.firstWhere((row) => row['id'] == coffee.id)['icon'] = 'future_icon';
    final tolerant = LedgerStore.decode(payload);
    expect(tolerant.categories[coffee.id]!.icon, 'future_icon');

    // Saving without the picker keeps the icon; inheriting clears it.
    await ledger.saveCategory('拿铁', MoneyKind.expense, 'lunch', id: coffee.id);
    expect(store.state.categories[coffee.id]!.icon, 'local_cafe');
    await ledger.saveCategory(
      '拿铁',
      MoneyKind.expense,
      'lunch',
      id: coffee.id,
      inheritIcon: true,
    );
    expect(store.state.categories[coffee.id]!.icon, isNull);
  });
  test('category labels drop the parent path unless the leaf repeats', () {
    final state = LedgerState.empty();
    expect(state.categoryLabel(null), '未分类');
    expect(state.categoryLabel('missing'), '未分类');
    expect(state.categoryLabel('breakfast'), '早餐');
    expect(state.categoryLabel('food'), '餐饮');
    // Two categories share the leaf name「其他」, so they keep their paths.
    expect(state.categoryLabel('other-food'), '餐饮 / 其他');
    expect(state.categoryLabel('other-expense'), '其他');
  });
}
