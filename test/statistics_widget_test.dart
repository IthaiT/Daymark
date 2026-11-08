import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'support/screenshot_fonts.dart';
import 'dart:io';

import 'package:daymark/application/journal_controller.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/model.dart';
import 'package:daymark/domain/item.dart';
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

  Future<void> mountStatistics(WidgetTester tester) async {
    final store = journal.store;
    journal.dispose();
    journal = JournalController(
      store,
      day: monday,
      clock: () => monday.add(const Duration(days: 6)),
      settings: const AppSettings(splitOverlap: true),
    );
    await journal.initialize();
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: daymarkTheme(),
        home: RepaintBoundary(
          key: const ValueKey('statistics-capture'),
          child: Scaffold(body: StatisticsScreen(journal: journal)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'two tags each cover 100 percent while the total stays one hour',
    (tester) async {
      await loadScreenshotFonts(tester);
      final store = journal.store;
      await store.replaceEvents({
        'multi': Event(
          'multi',
          '煮面听课',
          ['life', 'work'],
          monday.add(const Duration(hours: 9)),
          monday.add(const Duration(hours: 10)),
        ),
      });
      await mountStatistics(tester);
      expect(find.text('去重总时长 1h'), findsOneWidget);
      expect(find.text('1h · 100%'), findsNWidgets(2));
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('statistics-capture')),
      );
      final snapshot = (await tester.runAsync(
        () => boundary.toImage(pixelRatio: 1),
      ))!;
      final bytes = (await tester.runAsync(
        () => snapshot.toByteData(format: ui.ImageByteFormat.png),
      ))!;
      await tester.runAsync(
        () => File(
          '.test-artifacts/flutter-statistics-multitag.png',
        ).writeAsBytes(bytes.buffer.asUint8List()),
      );
      snapshot.dispose();

      await tester.tap(find.byKey(const ValueKey('stats-coverage-work-total')));
      await tester.pumpAndSettle();
      expect(find.text('去重总时长 1h'), findsOneWidget);
      expect(find.text('1h · 100%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'parent and child memberships deduplicate the parent and the total',
    (tester) async {
      final store = journal.store;
      await store.replaceEvents({});
      await store.replaceTags({
        'parent': Tag('parent', '父标签'),
        'child': Tag('child', '子标签', 'parent'),
        'sibling': Tag('sibling', '另一个根'),
      });
      await store.replaceEvents({
        'multi': Event(
          'multi',
          '多标签',
          ['parent', 'child', 'sibling'],
          monday.add(const Duration(hours: 9)),
          monday.add(const Duration(hours: 10)),
        ),
      });
      await mountStatistics(tester);
      expect(find.text('去重总时长 1h'), findsOneWidget);
      final parent = find.byKey(const ValueKey('stats-coverage-parent-total'));
      expect(
        find.descendant(of: parent, matching: find.text('1h · 100%')),
        findsOneWidget,
      );
      expect(find.text('1h · 100%'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tag-only and item-only events have independent fallback groups',
    (tester) async {
      final store = journal.store;
      await store.saveItem(const Item(id: 'p', name: '学习计划'));
      await store.replaceEvents({
        'tags': Event(
          'tags',
          '煮牛肉面',
          ['life'],
          monday.add(const Duration(hours: 9)),
          monday.add(const Duration(hours: 10)),
        ),
        'item': Event(
          'item',
          '学习',
          null,
          monday.add(const Duration(hours: 9)),
          monday.add(const Duration(hours: 10)),
          '',
          'p',
        ),
      });
      await mountStatistics(tester);
      expect(find.text('去重总时长 1h'), findsOneWidget);
      expect(find.text('无标签'), findsWidgets);
      expect(find.text('30m · 50%'), findsNWidgets(2));
      await tester.tap(find.text('事项').first);
      await tester.pumpAndSettle();
      expect(find.text('事项明细'), findsOneWidget);
      expect(find.text('未关联事项'), findsWidgets);
      expect(find.text('无标签'), findsNothing);
      expect(find.text('去重总时长 1h'), findsOneWidget);
      expect(find.text('30m · 50%'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets('edits an event and moves it to another tag', (tester) async {
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
    await tester.tap(find.text('归类到…'));
    await tester.pumpAndSettle();
    expect(find.text('归类 1 条记录'), findsOneWidget);
    // Formal records always keep at least one classification.
    expect(find.byKey(const ValueKey('tag-choice-unclassified')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tag-choice-linux')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(journal.store.events['work']!.tagId, 'linux');
    expect(find.textContaining('已移动 1 条记录'), findsOneWidget);
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
    expect(find.text('去重总时长 4h'), findsOneWidget);
    expect(find.text('1h'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
