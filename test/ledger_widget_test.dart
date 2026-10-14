import 'support/screenshot_fonts.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:daymark/application/journal_controller.dart';
import 'package:daymark/application/appearance_controller.dart';
import 'package:daymark/application/ledger_controller.dart';
import 'package:daymark/data/ledger_store.dart';
import 'package:daymark/data/appearance_store.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/ledger.dart';
import 'package:daymark/domain/appearance.dart';
import 'package:daymark/domain/model.dart' show Event;
import 'package:daymark/main.dart';
import 'package:daymark/ui/ledger_screen.dart';
import 'package:daymark/ui/ledger_sidebar.dart';
import 'package:daymark/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
    'Enter saves every filled row atomically and Tab reaches the next amount',
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
      final firstWrites = writes;
      await enter(tester);
      expect(writes, firstWrites + 1);
      expect(store.state.records.length, 2);
      expect(store.state.accounts[cashAccountId]!.balanceCents, 996400);
      expect(
        tester.widget<TextField>(quick('breakfast')).controller!.text,
        isEmpty,
      );
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
      expect(store.state.records.length, 3);
      expect(store.state.accounts[cashAccountId]!.balanceCents, 995200);
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
      expect(store.state.accounts[cashAccountId]!.balanceCents, 995200);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(store.state.accounts[cashAccountId]!.balanceCents, 993200);
      await shortcut(tester, LogicalKeyboardKey.keyZ);
      expect(store.state.records.length, 3);
      expect(store.state.accounts[cashAccountId]!.balanceCents, 995200);
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
      await tester.tap(find.text('收入标签'));
      await tester.pumpAndSettle();
      await tester.enterText(quick('salary'), '1000');
      await enter(tester);
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
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('month-expense'))).data,
        '支出  ¥ 100.00',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('month-income'))).data,
        '收入  ¥ 1000.00',
      );
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
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('month-expense'))).data,
        '支出  ¥ 5.00',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('month-income'))).data,
        '收入  ¥ 0.00',
      );
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
      final journalTheme = Theme.of(
        tester.element(find.byKey(const ValueKey('day-input'))),
      );
      await tester.tap(find.byKey(const ValueKey('mode-1')));
      await tester.pumpAndSettle();
      final ledgerTheme = Theme.of(tester.element(quick('lunch')));
      expect(ledgerTheme.colorScheme, journalTheme.colorScheme);
      expect(ledgerTheme.textTheme, journalTheme.textTheme);
      expect(ledgerTheme.textTheme.bodyMedium!.fontFamily, 'Noto Sans SC');
      await tester.enterText(quick('lunch'), '28');
      await tester.tap(find.byKey(const ValueKey('palette-rose')));
      await tester.pumpAndSettle();
      final changedTheme = Theme.of(tester.element(quick('lunch')));
      expect(changedTheme.colorScheme, isNot(journalTheme.colorScheme));
      expect(tester.widget<TextField>(quick('lunch')).controller!.text, '28');
      await tester.tap(find.byKey(const ValueKey('mode-0')));
      await tester.pumpAndSettle();
      expect(
        Theme.of(
          tester.element(find.byKey(const ValueKey('day-input'))),
        ).colorScheme,
        changedTheme.colorScheme,
      );
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
      await tester.tap(find.byKey(const ValueKey('palette-pine')));
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

  testWidgets('failed theme persistence retains the palette and money drafts', (
    tester,
  ) async {
    await open(tester);
    final journalStore = (await tester.runAsync(() => Store.open(directory)))!;
    final journal = JournalController(journalStore, day: day);
    addTearDown(journal.dispose);
    final preferences = (await tester.runAsync(
      () => AppearanceStore.open(
        directory,
        writer: (file, bytes) async {
          throw const FileSystemException('模拟配色保存失败');
        },
      ),
    ))!;
    final appearance = AppearanceController(preferences);
    addTearDown(appearance.dispose);
    await tester.pumpWidget(
      DaymarkApp(journal: journal, ledger: ledger, appearance: appearance),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mode-1')));
    await tester.pumpAndSettle();
    await tester.enterText(quick('lunch'), '31');
    await tester.tap(find.byKey(const ValueKey('palette-pine')));
    await tester.pumpAndSettle();
    expect(appearance.state.palette, AppPalette.slate);
    expect(find.textContaining('无法保存配色设置'), findsOneWidget);
    expect(tester.widget<TextField>(quick('lunch')).controller!.text, '31');
    expect(
      Theme.of(tester.element(quick('lunch'))).colorScheme,
      daymarkTheme().colorScheme,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'record context menu edits notes, deletes and supports keyboard undo',
    (tester) async {
      await open(tester);
      await ledger.saveInputs([expense(2800, 'lunch', notes: '原备注')]);
      await tester.pumpAndSettle();
      final id = store.state.records.keys.single;
      final row = find.byKey(ValueKey('money-record-$id'));
      expect(
        find.descendant(
          of: row,
          matching: find.byType(PopupMenuButton<String>),
        ),
        findsNothing,
      );
      await tester.tap(row, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('修改备注'));
      await tester.pumpAndSettle();
      final notesField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(notesField, '更新后的备注');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(store.state.records[id]!.notes, '更新后的备注');
      final focus = Focus.of(
        tester.element(
          find.descendant(of: row, matching: find.text('餐饮 / 午餐')),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除账单'));
      await tester.pumpAndSettle();
      expect(store.state.records, isEmpty);
      await shortcut(tester, LogicalKeyboardKey.keyZ);
      expect(store.state.records[id]!.notes, '更新后的备注');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('synthetic screenshots cover ledger and nested statistics', (
    tester,
  ) async {
    await loadScreenshotFonts(tester);
    final boundaryKey = GlobalKey();
    await open(tester);
    final journalStore = (await tester.runAsync(() => Store.open(directory)))!;
    await tester.runAsync(
      () => journalStore.replaceEvents({
        'ui-work': Event(
          'ui-work',
          '项目开发',
          'work',
          day.add(const Duration(hours: 9)),
          day.add(const Duration(hours: 10, minutes: 30)),
        ),
        'ui-rest': Event(
          'ui-rest',
          '休息',
          'life',
          day.add(const Duration(hours: 10, minutes: 30)),
          day.add(const Duration(hours: 11)),
        ),
      }),
    );
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
    await tester.tap(find.byKey(const ValueKey('mode-0')));
    await tester.pumpAndSettle();
    await screenshot('workspace-journal');
    await tester.tap(find.byKey(const ValueKey('mode-1')));
    await tester.pumpAndSettle();
    await ledger.saveInputs([
      expense(10000, 'housing'),
      expense(4500, 'clothing'),
      expense(3200, 'hobby'),
      expense(2500, 'shopping'),
      expense(1800, 'topup'),
      expense(1000, 'health'),
      expense(900, 'entertainment'),
      expense(700, 'daily'),
    ]);
    await tester.tap(find.text('分类统计'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stats-food-false')));
    await tester.pumpAndSettle();
    await screenshot('ledger-statistics');
    await tester.tap(find.byKey(const ValueKey('stats-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('按年'));
    await tester.pumpAndSettle();
    await screenshot('ledger-year-statistics');
    tester.view.physicalSize = const Size(1100, 740);
    await tester.pumpAndSettle();
    await screenshot('ledger-statistics-compact');
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1360, 900);
    await tester.pumpAndSettle();
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
      await tester.tap(find.byKey(const ValueKey('account-actions')));
      await tester.pumpAndSettle();
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
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('month-expense'))).data,
        '支出  ¥ 0.00',
      );
      await tester.tap(find.byKey(const ValueKey('account-actions')));
      await tester.pumpAndSettle();
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
    'category manager edits and adds without duplicate pin or row menus',
    (tester) async {
      await open(tester);
      await ledger.saveInputs([expense(2800, 'lunch')]);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('管理分类'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.star), findsNothing);
      expect(find.byTooltip('固定为常用'), findsNothing);
      expect(find.byTooltip('取消固定'), findsNothing);
      final lunch = find.byKey(const ValueKey('category-manage-lunch'));
      await tester.ensureVisible(lunch);
      await tester.tap(lunch);
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
      expect(find.byTooltip('标签操作'), findsNothing);
      expect(find.text('向上移'), findsNothing);
      expect(find.text('向下移'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'day arrows cross year boundaries and discard drafts on date change',
    (tester) async {
      await open(tester);
      final date = find.byKey(const ValueKey('money-date'));
      await tester.enterText(date, '2026-12-31');
      await tester.enterText(quick('lunch'), '28');
      await tester.tap(find.byKey(const ValueKey('notes-toggle-lunch')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('quick-notes-lunch')),
        '跨年草稿',
      );
      await tester.tap(find.byKey(const ValueKey('money-next-day')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(date).controller!.text, '2027-01-01');
      expect(
        tester.widget<TextField>(quick('lunch')).controller!.text,
        isEmpty,
      );
      expect(find.byKey(const ValueKey('quick-notes-lunch')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('money-previous-day')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(date).controller!.text, '2026-12-31');
      await tester.enterText(date, '0001-01-01');
      await tester.tap(find.byKey(const ValueKey('money-previous-day')));
      expect(tester.widget<TextField>(date).controller!.text, '0001-01-01');
      await tester.enterText(date, '9999-12-31');
      await tester.tap(find.byKey(const ValueKey('money-next-day')));
      expect(tester.widget<TextField>(date).controller!.text, '9999-12-31');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('visible note entry survives failure, saves and edits per bill', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('notes-toggle-lunch')));
    await tester.pumpAndSettle();
    final notes = find.byKey(const ValueKey('quick-notes-lunch'));
    await tester.enterText(quick('lunch'), '28');
    await tester.enterText(notes, '午饭\n同事聚餐');
    fail = true;
    await tester.tap(find.byKey(const ValueKey('save-all-money')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(notes).controller!.text, '午饭\n同事聚餐');
    expect(store.state.records, isEmpty);
    fail = false;
    await tester.tap(find.byKey(const ValueKey('save-all-money')));
    await tester.pumpAndSettle();
    final record = store.state.records.values.single;
    expect(record.notes, '午饭\n同事聚餐');
    expect(find.text(record.notes), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('money-record-${record.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('record-notes')), '更新备注');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(store.state.records[record.id]!.notes, '更新备注');
    expect(store.state.accounts[cashAccountId]!.balanceCents, 997200);
  });

  testWidgets(
    'ledger tree folds, right-click colors and drag moves preserve associations',
    (tester) async {
      await open(tester);
      await ledger.saveInputs([expense(2800, 'lunch')]);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ledger-fold-food')));
      await tester.pumpAndSettle();
      expect(quick('lunch'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('ledger-fold-food')));
      await tester.pumpAndSettle();
      expect(quick('lunch'), findsOneWidget);
      await tester.tap(find.text('午餐'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('修改标签'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('category-color-pink')));
      fail = true;
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(store.state.categories['lunch']!.color, isNull);
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('category-color-pink')),
            )
            .selected,
        isTrue,
      );
      fail = false;
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(store.state.categories['lunch']!.color, CategoryColor.pink);
      final source = tester.getCenter(find.text('午餐'));
      final target = tester.getCenter(find.text('住房'));
      final drag = await tester.startGesture(source);
      await tester.pump(const Duration(milliseconds: 300));
      await drag.moveTo(target);
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      expect(store.state.categories['lunch']!.parentId, 'housing');
      expect(store.state.records.values.single.categoryId, 'lunch');
      expect(store.state.categories['lunch']!.color, CategoryColor.pink);
      await shortcut(tester, LogicalKeyboardKey.keyZ);
      expect(store.state.categories['lunch']!.parentId, 'food');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'year totals and income drilldown fit desktop and preserve selected period',
    (tester) async {
      await open(tester, size: const Size(1100, 740));
      await ledger.saveInputs([
        expense(1000, 'lunch'),
        expense(2000, 'housing', date: DateTime.utc(2026, 1, 1)),
        expense(3000, 'daily', date: DateTime.utc(2025, 12, 31)),
        MoneyInput(
          kind: MoneyKind.income,
          amountCents: 4000,
          date: day,
          categoryId: 'salary',
        ),
        MoneyInput(
          kind: MoneyKind.income,
          amountCents: 5000,
          date: DateTime.utc(2026, 12, 31),
        ),
      ]);
      await ledger.transfer(cashAccountId, investmentAccountId, 6000, day);
      await tester.pumpAndSettle();
      await tester.tap(find.text('分类统计'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ledger-donut')), findsOneWidget);
      await tester.tap(find.text('按年'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('month-expense'))).data,
        '支出  ¥ 30.00',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('month-income'))).data,
        '收入  ¥ 90.00',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('money-month')))
            .controller!
            .text,
        '2026',
      );
      await tester.tap(find.text('收入'));
      await tester.pumpAndSettle();
      expect(find.text('全部收入'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('stats-unclassified-true')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('stats-salary-false')));
      await tester.pumpAndSettle();
      expect(find.text('工资（直接记录）'), findsOneWidget);
      expect(find.text('¥ 40.00  100.0%'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('money-previous-month')));
      await tester.pumpAndSettle();
      expect(find.text('本年暂无收入'), findsOneWidget);
      await tester.tap(find.text('支出'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('month-expense'))).data,
        '支出  ¥ 30.00',
      );
      await tester.tap(find.byKey(const ValueKey('money-next-month')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('流水'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('money-month')))
            .controller!
            .text,
        '2026-10',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('month-expense'))).data,
        '支出  ¥ 10.00',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'movement notes dialog preserves failed input and leaves balances unchanged',
    (tester) async {
      await open(tester);
      await ledger.transfer(
        cashAccountId,
        investmentAccountId,
        1000,
        day,
        notes: '原备注',
      );
      await tester.pumpAndSettle();
      final id = store.state.records.keys.single;
      await tester.tap(find.byKey(ValueKey('money-record-$id')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('bill-notes')),
        '转账备注\n第二行',
      );
      fail = true;
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(store.state.records[id]!.notes, '原备注');
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('bill-notes')))
            .controller!
            .text,
        '转账备注\n第二行',
      );
      fail = false;
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(store.state.records[id]!.notes, '转账备注\n第二行');
      expect(store.state.accounts[cashAccountId]!.balanceCents, 999000);
      expect(store.state.accounts[investmentAccountId]!.balanceCents, 301000);
    },
  );
  testWidgets(
    'physical Enter and numpad Enter save all kinds including collapsed drafts',
    (tester) async {
      await open(tester);
      await tester.enterText(quick('breakfast'), '8');
      await tester.enterText(quick('lunch'), '28');
      await tester.tap(find.byKey(const ValueKey('ledger-fold-food')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('收入标签'));
      await tester.pumpAndSettle();
      await tester.enterText(quick('salary'), '100');
      final beforeWrites = writes;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(writes, beforeWrites + 1);
      expect(store.state.records.length, 3);
      expect(store.state.accounts[cashAccountId]!.balanceCents, 1006400);
      await shortcut(tester, LogicalKeyboardKey.keyZ);
      expect(store.state.records, isEmpty);
      expect(store.state.accounts[cashAccountId]!.balanceCents, 1000000);
      await shortcut(tester, LogicalKeyboardKey.keyY);
      expect(store.state.records.length, 3);
      await tester.enterText(quick('salary'), '20');
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pumpAndSettle();
      expect(store.state.records.length, 4);
      expect(
        tester.widget<TextField>(quick('salary')).controller!.text,
        isEmpty,
      );
    },
  );

  testWidgets(
    'up and down move between visible amount fields and scroll while horizontal keys edit',
    (tester) async {
      await open(tester, size: const Size(1100, 740));
      await tester.enterText(quick('breakfast'), '8');
      await tester.enterText(quick('lunch'), '28');
      final breakfast = tester.widget<TextField>(quick('breakfast'));
      final lunch = tester.widget<TextField>(quick('lunch'));
      breakfast.focusNode!.requestFocus();
      breakfast.controller!.selection = const TextSelection.collapsed(
        offset: 0,
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(lunch.focusNode!.hasFocus, isTrue);
      expect(lunch.controller!.selection.extentOffset, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(lunch.controller!.selection.extentOffset, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(breakfast.focusNode!.hasFocus, isTrue);
      expect(breakfast.controller!.selection.extentOffset, 1);
      for (var i = 0; i < 25; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      expect(
        tester.widget<TextField>(quick('other-expense')).focusNode!.hasFocus,
        isTrue,
      );
      expect(
        tester.getRect(quick('other-expense')).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const ValueKey('ledger-tags'))).bottom,
        ),
      );
      expect(store.state.records, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native editing undo actions restore ledger transactions and retain unsaved text after failures',
    (tester) async {
      await open(tester);
      await tester.enterText(quick('breakfast'), '8');
      await tester.enterText(quick('lunch'), '28');
      await enter(tester);
      await tester.enterText(quick('lunch'), '83');
      await tester.pump(const Duration(milliseconds: 600));
      fail = true;
      Actions.invoke(
        FocusManager.instance.primaryFocus!.context!,
        const UndoTextIntent(SelectionChangedCause.keyboard),
      );
      await tester.pumpAndSettle();
      expect(store.state.records.length, 2);
      expect(tester.widget<TextField>(quick('lunch')).controller!.text, '83');
      expect(ledger.history.canUndo, isTrue);
      fail = false;
      Actions.invoke(
        FocusManager.instance.primaryFocus!.context!,
        const UndoTextIntent(SelectionChangedCause.keyboard),
      );
      await tester.pumpAndSettle();
      expect(store.state.records, isEmpty);
      expect(store.state.accounts[cashAccountId]!.balanceCents, 1000000);
      expect(tester.widget<TextField>(quick('lunch')).controller!.text, '83');
      fail = true;
      Actions.invoke(
        FocusManager.instance.primaryFocus!.context!,
        const RedoTextIntent(SelectionChangedCause.keyboard),
      );
      await tester.pumpAndSettle();
      expect(store.state.records, isEmpty);
      expect(ledger.history.canRedo, isTrue);
      expect(tester.widget<TextField>(quick('lunch')).controller!.text, '83');
      fail = false;
      Actions.invoke(
        FocusManager.instance.primaryFocus!.context!,
        const RedoTextIntent(SelectionChangedCause.keyboard),
      );
      await tester.pumpAndSettle();
      expect(store.state.records.length, 2);
      expect(store.state.accounts[cashAccountId]!.balanceCents, 996400);
      expect(tester.widget<TextField>(quick('lunch')).controller!.text, '83');
    },
  );

  testWidgets(
    'Enter validates hidden income drafts before writing any rows and reveals the bad field',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('收入标签'));
      await tester.pumpAndSettle();
      await tester.enterText(quick('salary'), 'bad');
      await tester.tap(find.text('支出标签'));
      await tester.pumpAndSettle();
      await tester.enterText(quick('lunch'), '28');
      final beforeWrites = writes;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(writes, beforeWrites);
      expect(store.state.records, isEmpty);
      expect(
        tester.widget<TextField>(quick('salary')).focusNode!.hasFocus,
        isTrue,
      );
      expect(tester.widget<TextField>(quick('salary')).controller!.text, 'bad');
      await tester.enterText(quick('salary'), '100');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(store.state.records.length, 2);
      expect(store.state.accounts[cashAccountId]!.balanceCents, 1007200);
    },
  );
  testWidgets(
    'daily flow totals include unloaded records and entry panel omits duplicate summaries',
    (tester) async {
      await open(tester, size: const Size(1100, 740));
      await ledger.saveInputs([
        for (var i = 0; i < 45; i++) expense(1000, 'lunch'),
        expense(2300, 'lunch', date: day.add(const Duration(days: 1))),
        MoneyInput(
          kind: MoneyKind.income,
          amountCents: 2500,
          date: day,
          categoryId: 'salary',
        ),
      ]);
      await ledger.transfer(cashAccountId, investmentAccountId, 10000, day);
      await ledger.calibrate(providentAccountId, 200100, day);
      await tester.pumpAndSettle();
      String label(String key) =>
          tester.widget<Text>(find.byKey(ValueKey(key))).data!;
      expect(label('day-expense-2026-10-11'), '支出  ¥ 450.00');
      expect(label('day-income-2026-10-11'), '收入  ¥ 25.00');
      expect(label('day-expense-2026-10-12'), '支出  ¥ 23.00');
      expect(find.byKey(const ValueKey('entry-day-expense')), findsNothing);
      expect(find.byKey(const ValueKey('entry-day-income')), findsNothing);
      final list = tester.widget<ListView>(
        find.byKey(const ValueKey('money-records')),
      );
      expect(list.childrenDelegate.estimatedChildCount, 40);
      await tester.tap(find.byKey(const ValueKey('money-next-day')));
      await tester.pumpAndSettle();
      expect(label('day-expense-2026-10-11'), '支出  ¥ 450.00');
      await tester.tap(find.byKey(const ValueKey('money-next-day')));
      await tester.pumpAndSettle();
      expect(find.textContaining('当日支出'), findsNothing);
      expect(find.textContaining('当日收入'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact ledger keeps income entry in the sidebar and removes redundant captions',
    (tester) async {
      await open(tester, size: const Size(1100, 740));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('money-date')))
            .decoration!
            .labelText,
        isNull,
      );
      expect(find.textContaining('可支配'), findsNothing);
      expect(find.byKey(const ValueKey('add-income')), findsNothing);
      expect(find.text('记收入'), findsNothing);
      await tester.tap(find.text('收入标签'));
      await tester.pumpAndSettle();
      expect(find.text('记收入'), findsOneWidget);
      await tester.enterText(quick('salary'), '100');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(store.state.records.values.single.kind, MoneyKind.income);
      expect(store.state.records.values.single.amountCents, 10000);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('day-income-2026-10-11')))
            .data,
        '收入  ¥ 100.00',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Enter confirms all inputs after Chinese composition has ended', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(quick('breakfast'), '8');
    await tester.enterText(quick('lunch'), '28');
    await tester.tap(find.byKey(const ValueKey('notes-toggle-lunch')));
    await tester.pumpAndSettle();
    final notes = find.byKey(const ValueKey('quick-notes-lunch'));
    await tester.enterText(notes, '午餐');
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '午餐',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(store.state.records, isEmpty);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '午餐',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(store.state.records.length, 2);
    expect(
      store.state.records.values
          .singleWhere((item) => item.categoryId == 'lunch')
          .notes,
      '午餐',
    );
  });

  testWidgets(
    'clicking a category focuses its amount without creating drag feedback',
    (tester) async {
      await open(tester);
      final label = find.text('早餐');
      final gesture = await tester.startGesture(
        tester.getCenter(label),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(2, 1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(label, findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(label, findsOneWidget);
      expect(
        tester.widget<TextField>(quick('breakfast')).focusNode!.hasFocus,
        isTrue,
      );
      await tester.enterText(quick('breakfast'), '12');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(store.state.records.values.single.amountCents, 1200);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'account menu keeps management reachable without discarding entry drafts',
    (tester) async {
      await open(tester);
      await tester.enterText(quick('breakfast'), '8');
      await tester.tap(find.byKey(const ValueKey('account-actions')));
      await tester.pumpAndSettle();
      expect(find.text('转账'), findsOneWidget);
      expect(find.text('余额校准'), findsOneWidget);
      await tester.tap(find.text('管理账户'));
      await tester.pumpAndSettle();
      expect(find.text('资金账户'), findsOneWidget);
      expect(find.text('新增账户'), findsOneWidget);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(quick('breakfast')).controller!.text,
        '8',
      );
      expect(store.state.records, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'dragging row edges reorders root and child tags and retains drafts on failure',
    (tester) async {
      await open(tester);
      await ledger.saveInputs([expense(2800, 'lunch')]);
      await tester.pumpAndSettle();
      await tester.enterText(quick('breakfast'), '8');
      Future<void> dragBefore(String source, String target) async {
        final pointer = await tester.startGesture(
          tester.getCenter(find.text(source)),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump(const Duration(milliseconds: 300));
        final targetRect = tester.getRect(
          find.byKey(ValueKey('ledger-tag-$target')),
        );
        await pointer.moveTo(targetRect.topLeft + const Offset(70, 2));
        await tester.pump();
        await pointer.up();
        await tester.pumpAndSettle();
      }

      fail = true;
      await dragBefore('交通', 'food');
      expect(store.state.categoryOrder, isEmpty);
      expect(
        tester.widget<TextField>(quick('breakfast')).controller!.text,
        '8',
      );
      fail = false;
      await dragBefore('交通', 'food');
      expect(
        store.state.categoryChildren(MoneyKind.expense, null).first.id,
        'transport',
      );
      await dragBefore('午餐', 'breakfast');
      expect(
        store.state.categoryChildren(MoneyKind.expense, 'food').first.id,
        'lunch',
      );
      expect(store.state.categories['lunch']!.parentId, 'food');
      expect(store.state.records.values.single.categoryId, 'lunch');
      expect(
        find.descendant(
          of: find.byType(LedgerSidebar),
          matching: find.byType(PopupMenuButton<String>),
        ),
        findsNothing,
      );
      await shortcut(tester, LogicalKeyboardKey.keyZ);
      expect(
        store.state.categoryChildren(MoneyKind.expense, 'food').first.id,
        'breakfast',
      );
      await shortcut(tester, LogicalKeyboardKey.keyY);
      expect(
        store.state.categoryChildren(MoneyKind.expense, 'food').first.id,
        'lunch',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
