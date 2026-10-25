import 'dart:convert';
import 'dart:io';

import 'package:daymark/application/journal_controller.dart';
import 'package:daymark/application/appearance_controller.dart';
import 'package:daymark/application/ledger_controller.dart';
import 'package:daymark/application/settings_controller.dart';
import 'package:daymark/data/ledger_store.dart';
import 'package:daymark/data/settings_store.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/model.dart';
import 'package:daymark/domain/journal_view_preferences.dart';
import 'package:daymark/main.dart';
import 'package:daymark/ui/timeline.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late JournalController journal;
  late SettingsStore settingsStore;
  var failSettingsWrites = false;
  String? savedSettings;
  final day = DateTime.utc(2026, 10, 7);

  setUp(() async {
    directory = await (await Directory(
      '.test-artifacts',
    ).create()).createTemp('settings-widgets-');
    failSettingsWrites = false;
    savedSettings = null;
    final store = await Store.open(directory, writer: (_, _) async {});
    await store.replaceEvents({
      'a': Event(
        'a',
        '做饭',
        'life',
        day.add(const Duration(hours: 13)),
        day.add(const Duration(hours: 15)),
      ),
      'b': Event(
        'b',
        '听播客',
        'work',
        day.add(const Duration(hours: 16)),
        day.add(const Duration(hours: 17)),
      ),
    });
    settingsStore = await SettingsStore.open(
      directory,
      writer: (file, bytes) async {
        if (failSettingsWrites) throw const FileSystemException('模拟失败');
        savedSettings = utf8.decode(bytes);
      },
    );
    journal = JournalController(
      store,
      day: day,
      settings: settingsStore.state,
      clock: () => day.add(const Duration(hours: 18)),
    );
    await journal.initialize();
  });

  tearDown(() async {
    journal.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> openSettings(WidgetTester tester) async {
    // Rebuild the controller inside the widget binding's clock zone so its
    // serialized write queue completes while the test pumps frames.
    final store = journal.store;
    journal.dispose();
    journal = JournalController(
      store,
      day: day,
      settings: settingsStore.state,
      clock: () => day.add(const Duration(hours: 18)),
    );
    await journal.initialize();
    final ledgerStore = (await tester.runAsync(
      () => LedgerStore.open(directory, writer: (_, _) async {}),
    ))!;
    final ledger = LedgerController(ledgerStore);
    addTearDown(ledger.dispose);
    final settings = SettingsController(settingsStore);
    addTearDown(settings.dispose);
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final appearance = AppearanceController();
    addTearDown(appearance.dispose);
    await appearance.setJournalView(JournalViewPreferences.fullDay);
    await tester.pumpWidget(
      DaymarkApp(
        journal: journal,
        ledger: ledger,
        settings: settings,
        appearance: appearance,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings')));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
  }

  bool autoUndefinedSwitch(WidgetTester tester) => tester
      .widget<SwitchListTile>(
        find.byKey(const ValueKey('setting-auto-undefined')),
      )
      .value;

  bool chipSelected(WidgetTester tester, int minutes) => tester
      .widget<ChoiceChip>(find.byKey(ValueKey('granularity-$minutes')))
      .selected;

  bool splitOverlapSwitch(WidgetTester tester) => tester
      .widget<SwitchListTile>(
        find.byKey(const ValueKey('setting-split-overlap')),
      )
      .value;

  testWidgets('dialog shows defaults and cancel changes nothing', (
    tester,
  ) async {
    await openSettings(tester);
    expect(autoUndefinedSwitch(tester), isTrue);
    expect(chipSelected(tester, 1), isTrue);
    expect(find.text('自动生成未定义事件'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsNothing);
    expect(journal.autoUndefined, isTrue);
    expect(savedSettings, isNull);
  });

  testWidgets('saving persists both settings and only hides undefined rows', (
    tester,
  ) async {
    expect(journal.rows.where((event) => event.isUndefined), isNotEmpty);
    await openSettings(tester);
    await tester.tap(find.byKey(const ValueKey('setting-auto-undefined')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('granularity-15')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-settings')));
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsNothing);
    expect(journal.autoUndefined, isFalse);
    expect(journal.dragMinutes, 15);
    expect(journal.rows.where((event) => event.isUndefined), isEmpty);
    expect(
      journal.store.events.values.where((event) => event.isUndefined),
      isNotEmpty,
    );
    expect(jsonDecode(savedSettings!), {
      'version': 1,
      'auto_undefined': false,
      'drag_minutes': 15,
      'split_overlap': false,
    });

    await tester.tap(find.byKey(const ValueKey('settings')));
    await tester.pumpAndSettle();
    expect(autoUndefinedSwitch(tester), isFalse);
    expect(chipSelected(tester, 15), isTrue);
  });

  testWidgets('saved granularity changes real timeline drags', (tester) async {
    await openSettings(tester);
    await tester.tap(find.byKey(const ValueKey('granularity-30')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-settings')));
    await tester.pumpAndSettle();

    Future<void> dragBy(int minutes) async {
      final rect = tester.getRect(find.byType(Timeline));
      final width = rect.width - 50;
      final gesture = await tester.startGesture(
        Offset(rect.left + 24 + width * 14.5 / 24, rect.top + 120),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveBy(Offset(width * minutes / 1440, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await dragBy(10);
    expect(
      journal.store.events['a']!.start,
      day.add(const Duration(hours: 13)),
    );
    await dragBy(20);
    expect(
      journal.store.events['a']!.start,
      day.add(const Duration(hours: 13, minutes: 30)),
    );
  });

  testWidgets('failed preference write keeps the dialog and input for retry', (
    tester,
  ) async {
    await openSettings(tester);
    await tester.tap(find.byKey(const ValueKey('setting-auto-undefined')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('granularity-30')));
    await tester.pumpAndSettle();
    failSettingsWrites = true;
    await tester.tap(find.byKey(const ValueKey('save-settings')));
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsOneWidget);
    expect(find.textContaining('模拟失败'), findsOneWidget);
    expect(autoUndefinedSwitch(tester), isFalse);
    expect(chipSelected(tester, 30), isTrue);
    expect(savedSettings, isNull);

    failSettingsWrites = false;
    await tester.tap(find.byKey(const ValueKey('save-settings')));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsNothing);
    expect(jsonDecode(savedSettings!), {
      'version': 1,
      'auto_undefined': false,
      'drag_minutes': 30,
      'split_overlap': false,
    });
  });

  testWidgets('split overlap switch saves the statistics policy', (
    tester,
  ) async {
    await openSettings(tester);
    expect(splitOverlapSwitch(tester), isFalse);
    await tester.tap(find.byKey(const ValueKey('setting-split-overlap')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-settings')));
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsNothing);
    expect(journal.splitOverlap, isTrue);
    expect(jsonDecode(savedSettings!), {
      'version': 1,
      'auto_undefined': true,
      'drag_minutes': 1,
      'split_overlap': true,
    });
  });
}
