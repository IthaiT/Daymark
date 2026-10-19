import 'dart:io';

import 'package:daymark/application/journal_controller.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/model.dart';
import 'package:daymark/domain/settings.dart';
import 'package:daymark/ui/statistics_screen.dart';
import 'package:daymark/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late JournalController journal;
  final monday = DateTime.utc(2026, 10, 12);
  setUp(() async {
    directory = await (await Directory(
      '.test-artifacts',
    ).create()).createTemp('statistics-');
    final store = await Store.open(directory, writer: (file, bytes) async {});
    await store.replaceEvents({
      'linux': Event(
        'linux',
        '内核调度',
        'linux',
        monday.add(const Duration(hours: 9)),
        monday.add(const Duration(hours: 10)),
      ),
      'work': Event(
        'work',
        '周会',
        'work',
        monday.add(const Duration(days: 2, hours: 9)),
        monday.add(const Duration(days: 2, hours: 11)),
      ),
      'free': Event(
        'free',
        '散步',
        null,
        monday.add(const Duration(days: 2, hours: 12)),
        monday.add(const Duration(days: 2, hours: 13)),
      ),
    });
    journal = JournalController(
      store,
      day: monday,
      clock: () => monday.add(const Duration(days: 6, hours: 20)),
    );
    await journal.initialize();
  });
  tearDown(() async {
    journal.dispose();
    await directory.delete(recursive: true);
  });

  testWidgets('statistics workspace builds without overflow', (tester) async {
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: daymarkTheme(),
        home: Scaffold(body: StatisticsScreen(journal: journal)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('统计'), findsOneWidget);
    expect(find.text('本周构成'), findsOneWidget);
    expect(find.text('标签明细'), findsOneWidget);
    expect(find.text('时段分布'), findsOneWidget);
    expect(find.text('近 8 周'), findsOneWidget);
    expect(find.textContaining('事件'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edits an event and moves it to unclassified', (tester) async {
    // Recreate the controller inside the widget test's zone so the serialized
    // mutation queue is driven by the test binding, not by setUp's zone.
    final store = journal.store;
    journal.dispose();
    journal = JournalController(
      store,
      day: monday,
      clock: () => monday.add(const Duration(days: 6, hours: 20)),
    );
    await journal.initialize();
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: daymarkTheme(),
        home: Scaffold(body: StatisticsScreen(journal: journal)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(find.text('完成'), findsOneWidget);
    await tester.tap(find.text('周会'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 条'), findsOneWidget);
    await tester.tap(find.text('移动到标签…'));
    await tester.pumpAndSettle();
    expect(find.text('移动 1 条事件'), findsOneWidget);
    final dialog = find.byType(AlertDialog);
    await tester.tap(find.descendant(of: dialog, matching: find.text('主业')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tag-choice-unclassified')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移动'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(journal.store.events['work']!.tagId, isNull);
    expect(find.textContaining('已移动 1 条事件'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('split overlap setting shares parallel time between tags', (
    tester,
  ) async {
    final store = journal.store;
    journal.dispose();
    await store.replaceEvents({});
    await store.replaceTags({
      for (var index = 0; index < 4; index++)
        'parallel-$index': Tag('parallel-$index', '并行 $index'),
    });
    await store.replaceEvents({
      for (var index = 0; index < 4; index++)
        'p-$index': Event(
          'p-$index',
          '并行事件 $index',
          'parallel-$index',
          monday.add(const Duration(hours: 8)),
          monday.add(const Duration(hours: 12)),
        ),
    });
    journal = JournalController(
      store,
      day: monday,
      clock: () => monday.add(const Duration(days: 6, hours: 20)),
    );
    await journal.initialize();
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: daymarkTheme(),
        home: Scaffold(body: StatisticsScreen(journal: journal)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('4h'), findsWidgets);

    await journal.applySettings(const AppSettings(splitOverlap: true));
    await tester.pumpAndSettle();
    expect(find.text('4h'), findsNothing);
    expect(find.text('1h'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
