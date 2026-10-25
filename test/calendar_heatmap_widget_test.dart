import 'dart:io';
import 'dart:ui' as ui;

import 'package:daymark/application/journal_controller.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/model.dart';
import 'package:daymark/domain/settings.dart';
import 'package:daymark/ui/calendar_heatmap.dart';
import 'package:daymark/ui/event_table.dart';
import 'package:daymark/ui/journal_screen.dart';
import 'package:daymark/ui/pickers.dart';
import 'package:daymark/ui/theme.dart';
import 'package:daymark/ui/timeline.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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

  testWidgets('adds repeated searches, excludes duplicates and removes chips', (
    tester,
  ) async {
    await open(tester);
    await heatmap(tester);
    final search = find.byKey(const ValueKey('activity-tag-picker'));
    Future<void> add(String query) async {
      await tester.enterText(search, query);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
    }

    await add('主业');
    await add('Linux');
    await add('未分类');
    expect(
      tester
          .widget<CalendarHeatmap>(find.byType(CalendarHeatmap))
          .selection
          .ids,
      {'work', 'linux', null},
    );
    expect(find.byType(InputChip), findsNWidgets(3));
    expect(find.text('累计 33 小时 00 分 · 3 个活跃日'), findsOneWidget);
    await tester.enterText(search, 'LINUX');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的标签'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('移除未分类'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CalendarHeatmap>(find.byType(CalendarHeatmap))
          .selection
          .ids,
      {'work', 'linux'},
    );
    expect(find.text('累计 32 小时 00 分 · 3 个活跃日'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('activity-clear-tags')));
    await tester.pumpAndSettle();
    expect(find.byType(InputChip), findsNothing);
    expect(
      tester
          .widget<CalendarHeatmap>(find.byType(CalendarHeatmap))
          .selection
          .isAll,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'day cells link both table modes to the selected tag union and descendants',
    (tester) async {
      await store.replaceEvents({
        ...store.events,
        'rest-day': Event(
          'rest-day',
          '休息记录',
          'rest',
          day.add(const Duration(hours: 20)),
          day.add(const Duration(hours: 21)),
        ),
        'overnight': Event(
          'overnight',
          '跨日工作',
          'linux',
          day.subtract(const Duration(hours: 1)),
          day.add(const Duration(hours: 1)),
        ),
        'unfinished': Event(
          'unfinished',
          '待补全工作',
          'linux',
          day.add(const Duration(hours: 7)),
          null,
        ),
      });
      await open(tester);
      final original = Map.of(store.events);
      await heatmap(tester);
      await select(tester, 'work');
      final search = find.byKey(const ValueKey('activity-tag-picker'));
      await tester.enterText(search, '休息');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.tap(find.byKey(const ValueKey('activity-day-2026-10-24')));
      await tester.pumpAndSettle();
      List<String> rows() => tester
          .widget<EventTable>(find.byType(EventTable))
          .events!
          .map((event) => event.id)
          .toList();
      expect(rows(), ['overnight', 'unfinished', 'work-2', 'rest-day']);
      expect(find.byKey(const ValueKey('row-free')), findsNothing);
      expect(find.text('跨日工作'), findsOneWidget);
      expect(find.text('待补全工作'), findsOneWidget);
      await tester.tap(find.text('汇总'));
      await tester.pumpAndSettle();
      expect(rows(), ['overnight', 'unfinished', 'work-2', 'rest-day']);
      expect(find.text('未分类 / 未定义'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('activity-day-2026-10-23')));
      await tester.pumpAndSettle();
      expect(rows(), ['work-1', 'overnight']);
      await tester.tap(find.text('时间轴'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('next-day')));
      await tester.pumpAndSettle();
      expect(rows(), journal!.rows.map((event) => event.id).toList());
      expect(rows(), contains('free'));
      expect(store.events, original);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unclassified table excludes gaps and tag changes clear selection',
    (tester) async {
      await open(tester);
      await heatmap(tester);
      await select(tester, 'work');
      await tester.tap(find.byKey(const ValueKey('cell-work-2-title')));
      await tester.pumpAndSettle();
      expect(journal!.selected, {'work-2'});
      await select(tester, 'rest');
      expect(journal!.selected, isEmpty);
      expect(find.byKey(const ValueKey('row-work-2')), findsNothing);
      final search = find.byKey(const ValueKey('activity-tag-picker'));
      await tester.enterText(search, '未分类');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.tap(find.byKey(const ValueKey('activity-day-2026-10-24')));
      await tester.pumpAndSettle();
      final table = tester.widget<EventTable>(find.byType(EventTable));
      expect(table.events!.map((event) => event.id), ['free']);
      expect(store.events.values.any((event) => event.isUndefined), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('filtered summary keeps the whole day overlap denominator', (
    tester,
  ) async {
    await store.replaceEvents({
      ...store.events,
      'free': store.events['free']!.copyWith(
        start: day.add(const Duration(hours: 8)),
        end: day.add(const Duration(hours: 20)),
      ),
    });
    await open(tester);
    await journal!.applySettings(const AppSettings(splitOverlap: true));
    await heatmap(tester);
    await select(tester, 'linux');
    await tester.tap(find.text('汇总'));
    await tester.pumpAndSettle();
    expect(find.text('单日峰值 11 小时 00 分'), findsOneWidget);
    expect(find.textContaining('6 小时 00 分'), findsOneWidget);
    expect(find.text('未分类 / 未定义'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'filtered table keeps new rows reachable through tag completion',
    (tester) async {
      await open(tester);
      await heatmap(tester);
      await select(tester, 'work');
      await tester.tap(find.byKey(const ValueKey('add-event')));
      await tester.pumpAndSettle();
      final id = journal!.drafts.keys.single;
      await tester.enterText(find.byKey(ValueKey('input-$id-title')), '新增工作');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('row-$id')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(ValueKey('input-$id-tag')), 'Linux');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(store.events[id]!.tagId, 'linux');
      expect(find.byKey(ValueKey('row-$id')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed edits block heatmap filter and day changes', (
    tester,
  ) async {
    await open(tester);
    await heatmap(tester);
    await select(tester, 'work');
    final cell = find.byKey(const ValueKey('cell-work-2-title'));
    await tester.tap(cell);
    await tester.pumpAndSettle();
    await tester.tap(cell);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('input-work-2-title')),
      '保留修改',
    );
    failWrites = true;
    await select(tester, 'rest');
    await tester.tap(find.byKey(const ValueKey('activity-day-2026-10-22')));
    await tester.pumpAndSettle();
    expect(journal!.day, day);
    expect(
      tester
          .widget<CalendarHeatmap>(find.byType(CalendarHeatmap))
          .selection
          .ids,
      {'work'},
    );
    expect(find.text('保留修改'), findsOneWidget);
    expect(store.events['work-2']!.title, '工作 12 小时');
    failWrites = false;
    await select(tester, 'rest');
    expect(store.events['work-2']!.title, '保留修改');
    expect(find.byKey(const ValueKey('row-work-2')), findsNothing);
    expect(tester.takeException(), isNull);
  });

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
      expect(find.textContaining('颜色按当前标签本年峰值'), findsNothing);
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
            .ids,
        {'linux'},
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
      await tester.tap(find.byKey(const ValueKey('tag-choice-unclassified')));
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

  testWidgets(
    'searches full paths without case sensitivity and confirms with keyboard',
    (tester) async {
      await open(tester);
      await heatmap(tester);
      final search = find.byKey(const ValueKey('activity-tag-picker'));
      await tester.tap(search);
      await tester.pumpAndSettle();
      expect(find.byType(TagChoices), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is ListTile && widget.selected,
        ),
        findsOneWidget,
      );
      await tester.enterText(search, '主业 / 嵌入式 / LINUX');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tag-choice-linux')), findsOneWidget);
      expect(find.byKey(const ValueKey('tag-choice-work')), findsNothing);
      expect(
        tester.widget<CalendarHeatmap>(find.byType(CalendarHeatmap)).selection,
        allActivityTags,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CalendarHeatmap>(find.byType(CalendarHeatmap))
            .selection
            .ids,
        {'linux'},
      );
      expect(find.byType(TagChoices), findsOneWidget);
      final input = find.descendant(
        of: search,
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(input).controller!.text, '');
      expect(find.text('单日峰值 12 小时 00 分'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'search navigates matches, cancels unknown queries and follows sidebar changes',
    (tester) async {
      await open(tester);
      await heatmap(tester);
      final search = find.byKey(const ValueKey('activity-tag-picker'));
      await tester.enterText(search, '主业');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CalendarHeatmap>(find.byType(CalendarHeatmap))
            .selection
            .ids,
        {'embedded'},
      );
      await select(tester, 'rest');
      final input = find.descendant(
        of: search,
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(input).controller!.text, '');
      await tester.enterText(search, '不存在的标签');
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的标签'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CalendarHeatmap>(find.byType(CalendarHeatmap))
            .selection
            .ids,
        {'rest'},
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, '');
      expect(find.byType(TagChoices), findsNothing);
      await tester.enterText(search, '全部');
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的标签'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        tester.widget<CalendarHeatmap>(find.byType(CalendarHeatmap)).selection,
        allActivityTags,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tag search leaves Enter and arrows to IME composition', (
    tester,
  ) async {
    await open(tester);
    await heatmap(tester);
    final search = find.byKey(const ValueKey('activity-tag-picker'));
    await tester.tap(search);
    await tester.pumpAndSettle();
    const composing = TextEditingValue(
      text: 'Linux',
      selection: TextSelection.collapsed(offset: 5),
      composing: TextRange(start: 0, end: 5),
    );
    tester.testTextInput.updateEditingValue(composing);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      tester.widget<CalendarHeatmap>(find.byType(CalendarHeatmap)).selection,
      allActivityTags,
    );
    expect(find.byType(TagChoices), findsOneWidget);
    tester.testTextInput.updateEditingValue(
      composing.copyWith(composing: TextRange.empty),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CalendarHeatmap>(find.byType(CalendarHeatmap))
          .selection
          .ids,
      {'linux'},
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'search results disambiguate equal leaf names by path and stable id',
    (tester) async {
      await store.replaceTags({
        ...store.tags,
        'other-linux': const Tag('other-linux', 'Linux', 'life'),
      });
      await open(tester);
      await heatmap(tester);
      final search = find.byKey(const ValueKey('activity-tag-picker'));
      await tester.enterText(search, 'Linux');
      await tester.pumpAndSettle();
      expect(find.text('主业 / 嵌入式 / Linux'), findsOneWidget);
      expect(find.text('生活 / Linux'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tag-choice-other-linux')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CalendarHeatmap>(find.byType(CalendarHeatmap))
            .selection
            .ids,
        {'other-linux'},
      );
      expect(find.text('本年暂无已完成记录'), findsOneWidget);
      expect(store.events['work-2']!.tagId, 'linux');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'renders synthetic multi-tag activity and linked rows screenshot',
    (tester) async {
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
        if (index % 3 == 0) {
          events['rest-$index'] = Event(
            'rest-$index',
            '合成休息记录',
            'rest',
            date.add(const Duration(hours: 20)),
            date.add(const Duration(hours: 21)),
          );
        }
      }
      events['sample-unclassified'] = Event(
        'sample-unclassified',
        '未分类记录',
        null,
        DateTime.utc(2026, 10, 22, 21, 30),
        DateTime.utc(2026, 10, 22, 22),
      );
      await store.replaceEvents(events);
      final boundaryKey = GlobalKey();
      await open(tester, boundary: boundaryKey);
      await heatmap(tester);
      await select(tester, 'work');
      await tester.enterText(
        find.byKey(const ValueKey('activity-tag-picker')),
        '休息',
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.tap(find.byKey(const ValueKey('activity-day-2026-10-22')));
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsNWidgets(2));
      expect(find.text('合成工作记录'), findsOneWidget);
      expect(find.text('合成休息记录'), findsOneWidget);
      expect(find.text('未分类记录'), findsNothing);
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
    },
  );
}
