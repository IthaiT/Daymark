import 'dart:io';
import 'dart:ui' as ui;

import 'package:daymark/application/journal_controller.dart';
import 'package:daymark/application/ledger_controller.dart';
import 'package:daymark/data/ledger_store.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/ledger.dart';
import 'package:daymark/main.dart';
import 'package:daymark/ui/ledger_screen.dart';
import 'package:daymark/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late LedgerStore store;
  late LedgerController ledger;
  var fail = false;
  var writes = 0;
  final day = DateTime.utc(2026, 10, 11);
  setUp(() async {
    directory = await (await Directory(
      '.test-artifacts',
    ).create()).createTemp('ledger-widgets-');
    fail = false;
    writes = 0;
    store = await LedgerStore.open(
      directory,
      writer: (file, bytes) async {
        writes++;
        if (fail) throw const FileSystemException('模拟保存失败');
      },
    );
  });
  tearDown(() async {
    ledger.dispose();
    await directory.delete(recursive: true);
  });
  Future<void> open(
    WidgetTester tester, {
    bool initialized = true,
    Size size = const Size(1360, 900),
  }) async {
    ledger = LedgerController(store, clock: () => day);
    if (initialized) {
      const opening = {
        cashAccountId: 1000000,
        providentAccountId: 200000,
        investmentAccountId: 300000,
      };
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
    }
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: daymarkTheme(),
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('zh', 'CN')],
      home: Scaffold(body: LedgerScreen(ledger: ledger)),
    );
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  Finder quick(String id) => find.byKey(ValueKey('quick-$id'));
  Future<void> enter(WidgetTester tester) async {
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  Future<void> shortcut(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool shift = false,
  }) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  MoneyInput expense(
    int amount,
    String category, {
    DateTime? date,
    String notes = '',
  }) => MoneyInput(
    kind: MoneyKind.expense,
    amountCents: amount,
    date: date ?? day,
    categoryId: category,
    notes: notes,
  );

  testWidgets('fresh ledger opens directly at zero and retains failed entry', (
    tester,
  ) async {
    await open(tester, initialized: false);
    expect(find.text('设置当前余额'), findsNothing);
    expect(find.text('¥ 0.00'), findsNWidgets(4));
    await tester.enterText(quick('lunch'), '28');
    fail = true;
    await enter(tester);
    await tester.pumpAndSettle();
    expect(store.state.totalCents, 0);
    expect(tester.widget<TextField>(quick('lunch')).controller!.text, '28');
    expect(find.textContaining('模拟保存失败'), findsOneWidget);
    fail = false;
    await tester.tap(quick('lunch'));
    await enter(tester);
    await tester.pumpAndSettle();
    expect(find.text('¥ -28.00'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('balance-cash')), findsOneWidget);
  });

  testWidgets(
    'Enter allows independent continuous entries, Tab reaches next amount, batch is atomic',
    (tester) async {
      await open(tester);
      expect(find.byIcon(Icons.undo), findsNothing);
      expect(find.byIcon(Icons.redo), findsNothing);
      expect(find.text('保存已填项目'), findsOneWidget);
      expect(find.textContaining('Ctrl+Enter'), findsNothing);
      await tester.enterText(quick('breakfast'), '8');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(quick('lunch')).focusNode!.hasFocus,
        isTrue,
      );
      await tester.enterText(quick('lunch'), '28');
      await enter(tester);
      expect(store.state.accounts[cashAccountId]!.balanceCents, 997200);
      expect(
        tester.widget<TextField>(quick('lunch')).controller!.text,
        isEmpty,
      );
      expect(
        tester.widget<TextField>(quick('lunch')).focusNode!.hasFocus,
        isTrue,
      );
      await tester.enterText(quick('lunch'), '12');
      await enter(tester);
      expect(store.state.records.length, 2);
      expect(store.state.accounts[cashAccountId]!.balanceCents, 996000);
      await tester.enterText(quick('dinner'), '20');
      final previousWrites = writes;
      await tester.tap(find.byKey(const ValueKey('save-all-money')));
      await tester.pumpAndSettle();
      expect(writes, previousWrites + 1);
      expect(store.state.records.length, 4);
      expect(store.state.accounts[cashAccountId]!.balanceCents, 993200);
      await tester.tap(quick('lunch'));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(store.state.accounts[cashAccountId]!.balanceCents, 996000);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(store.state.accounts[cashAccountId]!.balanceCents, 993200);
      await shortcut(tester, LogicalKeyboardKey.keyZ);
      expect(store.state.records.length, 2);
      expect(store.state.accounts[cashAccountId]!.balanceCents, 996000);
      await shortcut(tester, LogicalKeyboardKey.keyZ, shift: true);
      expect(store.state.accounts[cashAccountId]!.balanceCents, 993200);
    },
  );

  testWidgets(
    'failed Enter and invalid batch keep all inputs, retry saves once',
    (tester) async {
      await open(tester);
      final panelTop = tester.getTopLeft(find.text('记支出'));
      fail = true;
      await tester.enterText(quick('lunch'), '28');
      await enter(tester);
      expect(store.state.records, isEmpty);
      expect(store.state.accounts[cashAccountId]!.balanceCents, 1000000);
      expect(tester.widget<TextField>(quick('lunch')).controller!.text, '28');
      expect(find.byKey(const ValueKey('ledger-error-toast')), findsOneWidget);
      expect(tester.getTopLeft(find.text('记支出')), panelTop);
      fail = false;
      await tester.enterText(quick('breakfast'), 'wrong');
      await tester.tap(find.byKey(const ValueKey('save-all-money')));
      await tester.pumpAndSettle();
      expect(store.state.records, isEmpty);
      expect(find.text('早餐：请输入金额，最多保留两位小数。'), findsOneWidget);
      expect(
        tester.widget<TextField>(quick('breakfast')).focusNode!.hasFocus,
        isTrue,
      );
      expect(tester.getTopLeft(find.text('记支出')), panelTop);
      expect(tester.widget<TextField>(quick('lunch')).controller!.text, '28');
      await tester.tap(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.byType(IconButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      await tester.enterText(quick('breakfast'), '8');
      await tester.tap(find.byKey(const ValueKey('save-all-money')));
      await tester.pumpAndSettle();
      expect(store.state.records.length, 2);
      expect(store.state.accounts[cashAccountId]!.balanceCents, 996400);
    },
  );

  testWidgets(
    'income and editing type update cash, failed dialog preserves amount and notes',
    (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('add-income')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('record-amount')),
        '1000',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(store.state.accounts[cashAccountId]!.balanceCents, 1100000);
      final id = store.state.records.keys.single;
      await tester.tap(find.byKey(ValueKey('money-record-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('支出'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('record-amount')), '28');
      await tester.enterText(find.byKey(const ValueKey('record-notes')), '午饭');
      fail = true;
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(store.state.accounts[cashAccountId]!.balanceCents, 1100000);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('record-notes')))
            .controller!
            .text,
        '午饭',
      );
      fail = false;
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(store.state.accounts[cashAccountId]!.balanceCents, 997200);
      expect(store.state.records[id]!.kind, MoneyKind.expense);
    },
  );

  testWidgets(
    'selected month totals and nested expense percentages exclude income and transfers',
    (tester) async {
      await open(tester);
      await ledger.saveCategory('工作日', MoneyKind.expense, 'lunch');
      final nested = store.state.categories.values
          .singleWhere((item) => item.name == '工作日')
          .id;
      await ledger.saveInputs([
        expense(1000, 'food'),
        expense(2000, 'lunch'),
        expense(3000, 'breakfast'),
        expense(4000, nested),
        expense(500, 'other-food', date: DateTime.utc(2026, 9, 30)),
        MoneyInput(
          kind: MoneyKind.income,
          amountCents: 100000,
          date: day,
          categoryId: 'salary',
        ),
      ]);
      await ledger.transfer(cashAccountId, investmentAccountId, 20000, day);
      await ledger.calibrate(providentAccountId, 230000, day);
      await tester.pumpAndSettle();
      expect(find.text('支出  ¥ 100.00'), findsOneWidget);
      expect(find.text('收入  ¥ 1000.00'), findsOneWidget);
      await tester.tap(find.text('分类统计'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('stats-food-false')));
      await tester.pumpAndSettle();
      expect(find.text('¥ 60.00  60.0%'), findsOneWidget);
      expect(find.text('¥ 10.00  10.0%'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('stats-lunch-false')));
      await tester.pumpAndSettle();
      expect(find.text('¥ 40.00  66.7%'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('money-previous-month')));
      await tester.pumpAndSettle();
      expect(find.text('支出  ¥ 5.00'), findsOneWidget);
      expect(find.text('收入  ¥ 0.00'), findsOneWidget);
    },
  );

  testWidgets(
    'scrolling automatically expands history and excludes later months',
    (tester) async {
      await open(tester);
      await ledger.saveInputs([
        for (var i = 0; i < 100; i++)
          expense(
            100,
            'lunch',
            date: day.subtract(Duration(days: i)),
            notes: '流水$i',
          ),
        expense(100, 'lunch', date: DateTime.utc(2026, 11, 1), notes: '未来流水'),
      ]);
      await tester.pumpAndSettle();
      ListView list() =>
          tester.widget<ListView>(find.byKey(const ValueKey('money-records')));
      int count() => list().childrenDelegate.estimatedChildCount!;
      expect(count(), 40);
      list().controller!.jumpTo(list().controller!.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(count(), greaterThan(40));
      for (var i = 0; i < 4; i++) {
        list().controller!.jumpTo(list().controller!.position.maxScrollExtent);
        await tester.pumpAndSettle();
      }
      expect(count(), 100);
      expect(find.text('流水99'), findsOneWidget);
      expect(find.text('未来流水'), findsNothing);
      expect(find.text('查看更早'), findsNothing);
    },
  );

  testWidgets(
    'app switches modes and preserves money input; minimum desktop size fits',
    (tester) async {
      await open(tester, size: const Size(1100, 740));
      final journalStore = (await tester.runAsync(
        () => Store.open(directory),
      ))!;
      final journal = JournalController(journalStore, day: day);
      addTearDown(journal.dispose);
      await tester.pumpWidget(DaymarkApp(journal: journal, ledger: ledger));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mode-1')));
      await tester.pumpAndSettle();
      await tester.enterText(quick('lunch'), '28');
      await tester.tap(find.byKey(const ValueKey('mode-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mode-1')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(quick('lunch')).controller!.text, '28');
      await tester.tap(quick('lunch'));
      await enter(tester);
      expect(store.state.records.length, 1);
      await tester.tap(find.byKey(const ValueKey('mode-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mode-1')));
      await tester.pumpAndSettle();
      await shortcut(tester, LogicalKeyboardKey.keyZ);
      expect(store.state.records, isEmpty);
      await tester.tap(find.byKey(const ValueKey('mode-1')));
      await tester.pumpAndSettle();
      await shortcut(tester, LogicalKeyboardKey.keyY);
      expect(store.state.records.length, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('synthetic screenshots cover ledger and nested statistics', (
    tester,
  ) async {
    for (final entry in [
      ('Microsoft YaHei UI', 'C:/Windows/Fonts/msyh.ttc'),
      (
        'MaterialIcons',
        '.tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    ]) {
      if (File(entry.$2).existsSync()) {
        final bytes = (await tester.runAsync(
          () => File(entry.$2).readAsBytes(),
        ))!;
        final loader = FontLoader(entry.$1)
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await tester.runAsync(loader.load);
      }
    }
    final boundaryKey = GlobalKey();
    await open(tester);
    final journalStore = (await tester.runAsync(() => Store.open(directory)))!;
    final journal = JournalController(journalStore, day: day);
    addTearDown(journal.dispose);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: DaymarkApp(journal: journal, ledger: ledger),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mode-1')));
    await tester.pumpAndSettle();
    await ledger.saveInputs([
      expense(2800, 'lunch', notes: '工作日午餐'),
      expense(800, 'breakfast'),
      expense(1800, 'other-food'),
      expense(3500, 'dinner'),
      expense(300, 'transport'),
      MoneyInput(
        kind: MoneyKind.income,
        amountCents: 100000,
        date: day,
        categoryId: 'salary',
      ),
    ]);
    await tester.pumpAndSettle();
    Future<void> screenshot(String name) async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = (await tester.runAsync(
        () => boundary.toImage(pixelRatio: 1),
      ))!;
      final bytes = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.png),
      ))!;
      await tester.runAsync(
        () => File(
          '.test-artifacts/$name.png',
        ).writeAsBytes(bytes.buffer.asUint8List()),
      );
      image.dispose();
    }

    await screenshot('ledger');
    await tester.tap(find.text('分类统计'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stats-food-false')));
    await tester.pumpAndSettle();
    await screenshot('ledger-statistics');
    await tester.tap(find.text('流水'));
    await tester.pumpAndSettle();
    await tester.enterText(quick('breakfast'), 'a');
    await enter(tester);
    await screenshot('ledger-validation');
    expect(tester.widget<TextField>(quick('breakfast')).controller!.text, 'a');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'transfer and actual-balance calibration dialogs save and undo both accounts',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('转账'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('投资  ¥ 3000.00').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('movement-amount')),
        '100',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(store.state.accounts[cashAccountId]!.balanceCents, 990000);
      expect(store.state.accounts[investmentAccountId]!.balanceCents, 310000);
      expect(store.state.totalCents, 1500000);
      expect(find.text('支出  ¥ 0.00'), findsOneWidget);
      await tester.tap(find.text('余额校准'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('movement-amount')),
        '10001',
      );
      await tester.pumpAndSettle();
      expect(find.text('调整差额：+¥ 101.00'), findsOneWidget);
      fail = true;
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(store.state.accounts[cashAccountId]!.balanceCents, 990000);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('movement-amount')))
            .controller!
            .text,
        '10001',
      );
      fail = false;
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(store.state.accounts[cashAccountId]!.balanceCents, 1000100);
      await shortcut(tester, LogicalKeyboardKey.keyZ);
      expect(store.state.accounts[cashAccountId]!.balanceCents, 990000);
      await shortcut(tester, LogicalKeyboardKey.keyZ);
      expect(store.state.accounts[cashAccountId]!.balanceCents, 1000000);
      expect(store.state.accounts[investmentAccountId]!.balanceCents, 300000);
    },
  );

  testWidgets(
    'category manager adds, moves, renames, pins and reorders without losing records',
    (tester) async {
      await open(tester);
      await ledger.saveInputs([expense(2800, 'lunch')]);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('管理分类'));
      await tester.pumpAndSettle();
      final lunch = find.byKey(const ValueKey('category-manage-lunch'));
      final managerScroll = find.descendant(
        of: find.byKey(const ValueKey('category-manager-list')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(lunch, 180, scrollable: managerScroll);
      await tester.ensureVisible(lunch);
      await tester.tap(
        find.descendant(
          of: lunch,
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('重命名或移动'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('ledger-name')), '工作餐');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('一级分类').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(store.state.categories['lunch']!.parentId, isNull);
      expect(store.state.records.values.single.categoryId, 'lunch');
      tester.state<ScrollableState>(managerScroll).position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(lunch, 100, scrollable: managerScroll);
      await tester.ensureVisible(lunch);
      await tester.tap(
        find.descendant(of: lunch, matching: find.byTooltip('取消固定')),
      );
      await tester.pumpAndSettle();
      expect(store.state.pinned, isNot(contains('lunch')));
      await tester.tap(
        find.descendant(of: lunch, matching: find.byTooltip('固定为常用')),
      );
      await tester.pumpAndSettle();
      expect(store.state.pinned.last, 'lunch');
      await tester.tap(find.text('新增分类'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('ledger-name')), '甜点');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('餐饮').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(
        store.state.categories.values
            .singleWhere((item) => item.name == '甜点')
            .parentId,
        'food',
      );
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      final menu = find
          .ancestor(of: quick('lunch'), matching: find.byType(Row))
          .first;
      await tester.tap(
        find.descendant(
          of: menu,
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('向上移'));
      await tester.pumpAndSettle();
      expect(store.state.pinned[store.state.pinned.length - 2], 'lunch');
      expect(store.state.categories['lunch']!.name, '工作餐');
    },
  );
}
