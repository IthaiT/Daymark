import 'dart:io';
import 'dart:ui' as ui;

import 'package:daymark/application/journal_controller.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/model.dart';
import 'package:daymark/domain/settings.dart';
import 'package:daymark/ui/calendar_heatmap.dart';
import 'package:daymark/ui/journal_screen.dart';
import 'package:daymark/ui/theme.dart';
import 'package:daymark/ui/timeline.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/screenshot_fonts.dart';

void main() {
  late Directory directory;
  late Store store;
  JournalController? journal;
  var failWrites = false;
  final day = DateTime.utc(2026, 10, 24);

  setUp(() async {
    directory = await (await Directory(
      '.test-artifacts',
    ).create()).createTemp('activity-');
    failWrites = false;
    store = await Store.open(
      directory,
      writer: (_, _) async {
        if (failWrites) throw const FileSystemException('模拟写入失败');
      },
    );
    await store.replaceEvents({
      for (final (index, hours) in [9, 11, 12].indexed)
        'work-$index': Event(
          'work-$index',
          '工作 $hours 小时',
          index == 0 ? 'work' : 'linux',
          DateTime.utc(2026, 10, 22 + index, 8),
          DateTime.utc(2026, 10, 22 + index, 8 + hours),
        ),
      'free': Event(
        'free',
        '散步',
        null,
        day.add(const Duration(hours: 21)),
        day.add(const Duration(hours: 22)),
      ),
    });
  });

  tearDown(() async {
    journal?.dispose();
    journal = null;
    await directory.delete(recursive: true);
  });

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(1360, 900),
    GlobalKey? boundary,
  }) async {
    journal = JournalController(
      store,
      day: day,
      clock: () => day.add(const Duration(hours: 23)),
    );
    await journal!.initialize();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget app = MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: daymarkTheme(),
      home: JournalScreen(journal: journal!, showTitleBar: false),
    );
    if (boundary != null) app = RepaintBoundary(key: boundary, child: app);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  Future<void> heatmap(WidgetTester tester) async {
    await tester.tap(find.text('活动热力图'));
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(ValueKey('tag-$id')));
    await tester.pumpAndSettle();
  }

  Color? cellColor(WidgetTester tester, String date) =>
      tester.widget<Material>(find.byKey(ValueKey('activity-day-$date'))).color;

  testWidgets(
    'defaults to timeline; parent selection includes children and preserves rows',
    (tester) async {
      await open(tester);
      expect(find.byType(Timeline), findsOneWidget);
      expect(find.byType(CalendarHeatmap), findsNothing);
      final rows = journal!.rows;
      await heatmap(tester);
      await select(tester, 'work');
      expect(find.byKey(const ValueKey('tag-linux')), findsOneWidget);
      expect(find.text('单日峰值 12 小时 00 分'), findsOneWidget);
      expect(journal!.rows, rows);
      final shades = [
        '2026-10-22',
        '2026-10-23',
        '2026-10-24',
      ].map((date) => cellColor(tester, date)).toSet();
      expect(shades.length, 3);
      expect(cellColor(tester, '2026-10-24'), Colors.blue[900]);
      await select(tester, 'linux');
      expect(
        cellColor(tester, '2026-10-22'),
        daymarkTheme().colorScheme.surfaceContainerHighest,
      );
      expect(cellColor(tester, '2026-10-24'), Colors.blue[900]);
      await tester.tap(find.text('时间轴'));
      await tester.pumpAndSettle();
      expect(find.byType(Timeline), findsOneWidget);
      await heatmap(tester);
      expect(
        tester
            .widget<CalendarHeatmap>(find.byType(CalendarHeatmap))
            .selection
            .id,
        'linux',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hover describes a day; click selects it; years navigate with empty state',
    (tester) async {
      await open(tester);
      await heatmap(tester);
      await select(tester, 'work');
      final cell = find.byKey(const ValueKey('activity-day-2026-10-22'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(cell));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('2026-10-22 · 主业\n9 小时 00 分'), findsOneWidget);
      await tester.tap(cell);
      await tester.pumpAndSettle();
      expect(journal!.day, DateTime.utc(2026, 10, 22));
      expect(find.text('工作 9 小时'), findsOneWidget);
      expect(find.text('单日峰值 12 小时 00 分'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('activity-next-year')));
      await tester.pumpAndSettle();
      expect(journal!.day.year, 2027);
      expect(find.text('本年暂无已完成记录'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('activity-previous-year')));
      await tester.pumpAndSettle();
      expect(find.text('单日峰值 12 小时 00 分'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unclassified excludes derived gaps and edits rescale immediately',
    (tester) async {
      await open(tester);
      await heatmap(tester);
      await tester.tap(find.byKey(const ValueKey('activity-tag-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('未分类').last);
      await tester.pumpAndSettle();
      expect(find.text('单日峰值 1 小时 00 分'), findsOneWidget);
      await select(tester, 'work');
      final before = cellColor(tester, '2026-10-22');
      await journal!.updateEvent(
        store.events['work-2']!.copyWith(
          start: day,
          end: day.add(const Duration(hours: 20)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('单日峰值 20 小时 00 分'), findsOneWidget);
      expect(cellColor(tester, '2026-10-22'), isNot(before));
      await journal!.undo();
      await tester.pumpAndSettle();
      expect(cellColor(tester, '2026-10-22'), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'deleted selected tag falls back; split overlap setting updates graph',
    (tester) async {
      await open(tester);
      await heatmap(tester);
      await select(tester, 'rest');
      await journal!.deleteTag('rest');
      await tester.pumpAndSettle();
      expect(
        tester.widget<CalendarHeatmap>(find.byType(CalendarHeatmap)).selection,
        allActivityTags,
      );
      await journal!.updateEvent(
        store.events['free']!.copyWith(
          start: day.add(const Duration(hours: 8)),
          end: day.add(const Duration(hours: 20)),
        ),
      );
      await select(tester, 'linux');
      expect(find.text('单日峰值 12 小时 00 分'), findsOneWidget);
      await journal!.applySettings(const AppSettings(splitOverlap: true));
      await tester.pumpAndSettle();
      expect(find.text('单日峰值 11 小时 00 分'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed inline save retains input and blocks chart switch', (
    tester,
  ) async {
    await open(tester);
    final cell = find.byKey(const ValueKey('cell-work-2-title'));
    await tester.tap(cell);
    await tester.pumpAndSettle();
    await tester.tap(cell);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('input-work-2-title'));
    await tester.enterText(field, '保留输入');
    failWrites = true;
    await heatmap(tester);
    expect(find.byType(Timeline), findsOneWidget);
    expect(find.byType(CalendarHeatmap), findsNothing);
    expect(find.text('保留输入'), findsOneWidget);
    expect(store.events['work-2']!.title, '工作 12 小时');
    failWrites = false;
    await heatmap(tester);
    expect(find.byType(CalendarHeatmap), findsOneWidget);
    expect(store.events['work-2']!.title, '保留输入');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compact layout scrolls without overflow and leap year has 366 cells',
    (tester) async {
      await open(tester, size: const Size(760, 440));
      await heatmap(tester);
      expect(tester.takeException(), isNull);
      await journal!.setDay(DateTime.utc(2024, 2, 29));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Material &&
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'activity-day-',
              ),
        ),
        findsNWidgets(366),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('renders synthetic annual work activity screenshot', (
    tester,
  ) async {
    await loadScreenshotFonts(tester);
    final events = <String, Event>{};
    for (var index = 0; index < 300; index++) {
      final date = DateTime.utc(2026).add(Duration(days: index));
      if (date.weekday > 5 || index % 23 == 0) continue;
      final hours = index % 11 == 0
          ? 12
          : index % 7 == 0
          ? 11
          : 9;
      events['sample-$index'] = Event(
        'sample-$index',
        '合成工作记录',
        'work',
        date.add(const Duration(hours: 8)),
        date.add(Duration(hours: 8 + hours)),
      );
    }
    await store.replaceEvents(events);
    final boundaryKey = GlobalKey();
    await open(tester, boundary: boundaryKey);
    await heatmap(tester);
    await select(tester, 'work');
    await tester.tap(find.byKey(const ValueKey('activity-day-2026-10-22')));
    await tester.pumpAndSettle();
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
        '.test-artifacts/tag-activity-heatmap.png',
      ).writeAsBytes(bytes.buffer.asUint8List()),
    );
    image.dispose();
    expect(tester.takeException(), isNull);
  });
}
