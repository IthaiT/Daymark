import 'dart:io';

import 'package:daymark/application/appearance_controller.dart';
import 'package:daymark/application/journal_controller.dart';
import 'package:daymark/data/appearance_store.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/appearance.dart';
import 'package:daymark/domain/journal_view_preferences.dart';
import 'package:daymark/domain/model.dart';
import 'package:daymark/main.dart';
import 'package:daymark/ui/event_table.dart';
import 'package:daymark/ui/tag_sidebar.dart';
import 'package:daymark/ui/timeline.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late JournalController journal;
  late AppearanceStore appearanceStore;
  var failAppearance = false;
  final day = DateTime.utc(2026, 10, 24);
  DateTime at(int minute) => day.add(Duration(minutes: minute));

  setUp(() async {
    directory = await (await Directory(
      '.test-artifacts',
    ).create(recursive: true)).createTemp('focus-widgets-');
    final store = await Store.open(directory, writer: (_, _) async {});
    await store.replaceEvents({
      'sleep': Event('sleep', '日常睡眠', 'life', at(0), at(720)),
      'a': Event('a', '项目甲', 'work', at(600), at(660)),
      'b': Event('b', '项目乙', 'side', at(780), at(840)),
      'free': Event('free', '未分类的真实记录', null, at(900), at(930)),
    });
    journal = JournalController(store, day: day, clock: () => at(1000));
    await journal.initialize();
    failAppearance = false;
    appearanceStore = await AppearanceStore.open(
      directory,
      writer: (_, _) async {
        if (failAppearance) throw const FileSystemException('模拟外观写入失败');
      },
    );
  });

  tearDown(() async {
    journal.dispose();
    await directory.delete(recursive: true);
  });

  Future<AppearanceController> open(
    WidgetTester tester, {
    bool namedGap = false,
    bool shared = false,
    bool auto = true,
  }) async {
    final store = journal.store;
    journal.dispose();
    journal = JournalController(store, day: day, clock: () => at(1000));
    await journal.initialize();
    await journal.applySettings(
      journal.settings.copyWith(autoUndefined: auto, splitOverlap: shared),
    );
    if (namedGap) {
      final gap = journal.rows.firstWhere((event) => event.isUndefined);
      await journal.editCell(gap.id, EventColumn.title, '已经填写的空档');
    }
    final appearance = AppearanceController(appearanceStore);
    addTearDown(appearance.dispose);
    await appearance.setTagStyle('life', TagColor.orange, TagDisplay.routine);
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      DaymarkApp(journal: journal, appearance: appearance),
    );
    await tester.pumpAndSettle();
    return appearance;
  }

  Future<void> menu(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('journal-display')));
    await tester.pumpAndSettle();
  }

  Offset point(WidgetTester tester, TimelineState state, int minute) =>
      tester.getTopLeft(find.byType(Timeline)) +
      Offset(24 + state.axis.x(at(minute)) - state.horizontal.offset, 100);

  Future<void> toggleUnclassified(WidgetTester tester) async {
    await menu(tester);
    await tester.tap(find.byKey(const ValueKey('view-unclassified')));
    await tester.pumpAndSettle();
  }

  Future<void> hiddenEvents(WidgetTester tester) async {
    await menu(tester);
    await tester.tap(find.byKey(const ValueKey('view-hidden-events')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'heatmap tag filters and timeline display choices remain independent',
    (tester) async {
      await open(tester);
      await toggleUnclassified(tester);
      expect(find.byKey(const ValueKey('row-sleep')), findsNothing);
      expect(find.byKey(const ValueKey('row-free')), findsNothing);
      await tester.tap(find.text('活动热力图'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('row-sleep')), findsOneWidget);
      expect(find.byKey(const ValueKey('row-free')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tag-work')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('row-a')), findsOneWidget);
      for (final id in ['sleep', 'b', 'free']) {
        expect(find.byKey(ValueKey('row-$id')), findsNothing);
      }
      await tester.tap(find.text('时间轴'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('row-a')), findsOneWidget);
      expect(find.byKey(const ValueKey('row-b')), findsOneWidget);
      expect(find.byKey(const ValueKey('row-sleep')), findsNothing);
      expect(find.byKey(const ValueKey('row-free')), findsNothing);
      await menu(tester);
      await tester.tap(find.byKey(const ValueKey('view-full-day')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('row-sleep')), findsOneWidget);
      expect(find.byKey(const ValueKey('row-free')), findsNothing);
      await tester.tap(find.text('活动热力图'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('row-a')), findsOneWidget);
      expect(find.byKey(const ValueKey('row-b')), findsNothing);
    },
  );

  testWidgets('all hidden records remain inspectable without any axis folds', (
    tester,
  ) async {
    await journal.store.replaceEvents({
      'sleep': Event('sleep', '睡觉', 'life', at(0), at(720)),
      'meal': Event('meal', '早餐 买菜', null, at(720), at(900)),
      'other': Event('other', '午餐 看番', null, at(900), at(960)),
    });
    final appearance = await open(tester);
    final before = Map.of(journal.store.events);
    for (final preset in JournalViewPreset.values) {
      await appearance.setJournalView(
        JournalViewPreferences(preset: preset, showUnclassified: false),
      );
      await tester.pumpAndSettle();
      expect(
        tester.state<TimelineState>(find.byType(Timeline)).axis.folds,
        isEmpty,
      );
      await hiddenEvents(tester);
      final dialog = find.byKey(const ValueKey('hidden-events-dialog'));
      final table = tester.widget<DataTable>(
        find.descendant(of: dialog, matching: find.byType(DataTable)),
      );
      final focused = preset == JournalViewPreset.focused;
      expect(table.rows.length, focused ? 3 : 2);
      expect(
        find.descendant(of: dialog, matching: find.text('睡觉')),
        focused ? findsOneWidget : findsNothing,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('早餐 买菜')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('午餐 看番')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('2026-10-24 12:00:00')),
        focused ? findsNWidgets(2) : findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('生活')),
        focused ? findsOneWidget : findsNothing,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('未分类')),
        findsNWidgets(2),
      );
      expect(
        find.descendant(of: dialog, matching: find.text('显示完整一天')),
        findsNothing,
      );
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(appearance.state.journalView.preset, preset);
      expect(appearance.state.journalView.showUnclassified, isFalse);
      expect(journal.store.events, before);
    }
  });

  testWidgets(
    'global hidden records include unclassified and overlapping background rows',
    (tester) async {
      await open(tester, namedGap: true);
      await toggleUnclassified(tester);
      await hiddenEvents(tester);
      final table = tester.widget<DataTable>(find.byType(DataTable));
      expect(table.rows.length, 4);
      expect(find.text('日常睡眠'), findsOneWidget);
      expect(find.text('已经填写的空档'), findsOneWidget);
      expect(find.text('未分类的真实记录'), findsOneWidget);
      for (final heading in ['名称', '标签', '开始时间', '结束时间', '本日用时']) {
        expect(
          find.descendant(
            of: find.byType(DataTable),
            matching: find.text(heading),
          ),
          findsOneWidget,
        );
      }
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'hidden detail rows retain duplicates, overnight dates and incomplete inputs in a small dialog',
    (tester) async {
      await journal.store.replaceEvents({
        'sleep': Event('sleep', '同名事项', 'life', at(-60), at(60)),
        'other': Event('other', '同名事项', null, at(600), at(660), '保留的备注'),
        'pending': Event('pending', '待补时间', null, at(900), null),
      });
      await open(tester, auto: false);
      await toggleUnclassified(tester);
      await hiddenEvents(tester);
      tester.view.physicalSize = const Size(1100, 700);
      await tester.pumpAndSettle();
      expect(find.byType(DataTable), findsOneWidget);
      expect(tester.widget<DataTable>(find.byType(DataTable)).rows.length, 3);
      expect(find.text('同名事项'), findsNWidgets(2));
      expect(find.text('2026-10-23 23:00:00'), findsOneWidget);
      expect(find.text('待补全'), findsNWidgets(2));
      expect(find.text('保留的备注'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'one unclassified choice filters both surfaces and survives mode changes',
    (tester) async {
      final appearance = await open(tester, namedGap: true);
      final before = Map.of(journal.store.events);
      final gap = journal.rows.firstWhere(
        (event) => event.isUndefined && event.title == '已经填写的空档',
      );
      final timeline = tester.state<TimelineState>(find.byType(Timeline));
      await menu(tester);
      expect(find.text('显示日常背景'), findsNothing);
      expect(find.text('显示未定义空档'), findsNothing);
      expect(find.text('显示未分类事项'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('view-unclassified')));
      await tester.pumpAndSettle();
      expect(find.text('显示：关注事项'), findsOneWidget);
      expect(appearance.state.journalView.showUnclassified, isFalse);
      expect(find.byKey(const ValueKey('row-free')), findsNothing);
      expect(find.byKey(ValueKey('row-${gap.id}')), findsNothing);
      expect(timeline.axis.visibleDuration, const Duration(minutes: 120));
      expect(
        find.descendant(
          of: find.byType(TagSidebar),
          matching: find.text('未分类'),
        ),
        findsNothing,
      );
      await menu(tester);
      await tester.tap(find.byKey(const ValueKey('view-full-day')));
      await tester.pumpAndSettle();
      expect(find.text('显示：完整一天'), findsOneWidget);
      expect(find.byKey(const ValueKey('row-sleep')), findsOneWidget);
      expect(find.byKey(const ValueKey('row-free')), findsNothing);
      expect(timeline.axis.isFolded, isFalse);
      expect(appearance.state.journalView.showUnclassified, isFalse);
      expect(journal.store.events, before);
      expect(journal.autoUndefined, isTrue);
      await toggleUnclassified(tester);
      expect(find.byKey(const ValueKey('row-free')), findsOneWidget);
      expect(find.byKey(ValueKey('row-${gap.id}')), findsOneWidget);
      await toggleUnclassified(tester);
      await journal.shiftDay(1);
      await tester.pumpAndSettle();
      expect(appearance.state.journalView.showUnclassified, isFalse);
      expect(find.text('显示：完整一天'), findsOneWidget);
    },
  );

  testWidgets('unclassified drafts stay visible for editing when excluded', (
    tester,
  ) async {
    final appearance = await open(tester);
    await toggleUnclassified(tester);
    await tester.tap(find.text('新增事件'));
    await tester.pumpAndSettle();
    final draft = journal.drafts.values.single;
    expect(draft.tagId, isNull);
    expect(appearance.state.journalView.showUnclassified, isFalse);
    expect(find.byKey(ValueKey('row-${draft.id}')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(journal.drafts, isEmpty);
  });

  testWidgets('excluding parallel unclassified time preserves allocation', (
    tester,
  ) async {
    await journal.store.replaceEvents({
      'a': Event('a', '项目甲', 'work', at(600), at(660)),
      'free': Event('free', '并行未分类', null, at(600), at(660)),
    });
    await open(tester, shared: true);
    await toggleUnclassified(tester);
    await tester.tap(find.text('汇总'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('row-free')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('row-a')),
        matching: find.text('30 分钟'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'one display menu filters both surfaces without changing records',
    (tester) async {
      final appearance = await open(tester, namedGap: true);
      final before = Map.of(journal.store.events);
      expect(find.text('显示：关注事项'), findsOneWidget);
      expect(find.byKey(const ValueKey('row-sleep')), findsNothing);
      expect(find.byKey(const ValueKey('row-free')), findsOneWidget);
      expect(find.text('已经填写的空档'), findsOneWidget);
      expect(find.byType(Timeline), findsOneWidget);
      await menu(tester);
      await tester.tap(find.byKey(const ValueKey('view-full-day')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('row-sleep')), findsOneWidget);
      expect(appearance.state.journalView, JournalViewPreferences.fullDay);
      expect(journal.autoUndefined, isTrue);
      expect(journal.store.events, before);
      await journal.shiftDay(1);
      await tester.pumpAndSettle();
      expect(find.text('显示：完整一天'), findsOneWidget);
    },
  );

  testWidgets(
    'disabled automatic gaps cannot be enabled through a view choice',
    (tester) async {
      await open(tester, auto: false);
      await menu(tester);
      expect(find.text('显示日常背景'), findsNothing);
      expect(find.text('显示未定义空档'), findsNothing);
      final item = tester.widget<PopupMenuItem<Object?>>(
        find.byKey(const ValueKey('view-unclassified')),
      );
      expect(item.enabled, isTrue);
      await tester.tap(find.byKey(const ValueKey('view-unclassified')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('row-free')), findsNothing);
      await menu(tester);
      await tester.tap(find.byKey(const ValueKey('view-full-day')));
      await tester.pumpAndSettle();
      expect(journal.autoUndefined, isFalse);
      expect(find.byKey(const ValueKey('row-sleep')), findsOneWidget);
      expect(journal.rows.where((event) => event.isUndefined), isEmpty);
    },
  );

  testWidgets(
    'failed view persistence retains the prior filter and allows retry',
    (tester) async {
      final appearance = await open(tester);
      failAppearance = true;
      await menu(tester);
      await tester.tap(find.byKey(const ValueKey('view-full-day')));
      await tester.pumpAndSettle();
      expect(find.text('操作未完成'), findsOneWidget);
      expect(appearance.state.journalView, JournalViewPreferences.focused);
      expect(find.byKey(const ValueKey('row-sleep')), findsNothing);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      failAppearance = false;
      await menu(tester);
      await tester.tap(find.byKey(const ValueKey('view-full-day')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('row-sleep')), findsOneWidget);
    },
  );

  testWidgets('hiding a parallel background does not redistribute its time', (
    tester,
  ) async {
    await open(tester, shared: true);
    await tester.tap(find.text('汇总'));
    await tester.pumpAndSettle();
    expect(find.text('当前视图汇总'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('row-a')),
        matching: find.text('30 分钟'),
      ),
      findsOneWidget,
    );
    expect(find.byType(EventTable), findsOneWidget);
  });

  testWidgets('folds recover space without hiding overlapping visible time', (
    tester,
  ) async {
    await open(tester);
    final state = tester.state<TimelineState>(find.byType(Timeline));
    expect(state.axis.isFolded, isTrue);
    expect(state.axis.visibleDuration, const Duration(minutes: 150));
    expect(
      state.axis.pixelsPerMinute * 150 / state.axis.width,
      greaterThan(.79),
    );
    expect(state.axis.foldAt(state.axis.x(at(630))), isNull);
    final fold = state.axis.folds.firstWhere((span) => span.start == at(660));
    final origin = tester.getTopLeft(find.byType(Timeline));
    await tester.tapAt(origin + Offset(24 + fold.left + fold.width / 2, 100));
    await tester.pumpAndSettle();
    expect(find.text('折叠时段的事项'), findsOneWidget);
    expect(find.textContaining('11:00 — 13:00'), findsOneWidget);
    expect(tester.widget<DataTable>(find.byType(DataTable)).rows.length, 2);
    expect(find.text('显示完整一天'), findsNothing);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(state.axis.isFolded, isTrue);
    await menu(tester);
    await tester.tap(find.byKey(const ValueKey('view-full-day')));
    await tester.pumpAndSettle();
    expect(state.axis.isFolded, isFalse);
    expect(find.byKey(const ValueKey('row-sleep')), findsOneWidget);
  });

  testWidgets(
    'focused drag expands temporarily and preserves minute precision',
    (tester) async {
      await open(tester);
      final state = tester.state<TimelineState>(find.byType(Timeline));
      final scale = state.axis.pixelsPerMinute;
      final start = point(tester, state, 630);
      final drag = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await drag.moveTo(start + Offset(7 * scale, 0));
      await tester.pumpAndSettle();
      expect(state.axis.isFolded, isFalse);
      await drag.moveTo(start + Offset(12 * scale, 0));
      await tester.pumpAndSettle();
      await drag.up();
      await tester.pumpAndSettle();
      expect(state.axis.isFolded, isTrue);
      expect(journal.event('a')!.start, at(612));
      expect(journal.event('a')!.end, at(672));
      expect(state.horizontal.offset, 0);
    },
  );

  testWidgets('focused resize can enter folded time without jumping', (
    tester,
  ) async {
    await open(tester);
    final state = tester.state<TimelineState>(find.byType(Timeline));
    final scale = state.axis.pixelsPerMinute;
    final start = point(tester, state, 660);
    final drag = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await drag.moveTo(start + Offset(7 * scale, 0));
    await tester.pumpAndSettle();
    await drag.up();
    await tester.pumpAndSettle();
    expect(journal.event('a')!.start, at(600));
    expect(journal.event('a')!.end, at(667));
  });

  testWidgets('zoom and context creation use the folded time coordinates', (
    tester,
  ) async {
    await open(tester);
    final state = tester.state<TimelineState>(find.byType(Timeline));
    final anchor = point(tester, state, 630);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(
      PointerScrollEvent(position: anchor, scrollDelta: const Offset(0, -120)),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect((point(tester, state, 630).dx - anchor.dx).abs(), lessThan(1));
    final mouse = await tester.startGesture(
      point(tester, state, 630),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('在此新增事件'));
    await tester.pumpAndSettle();
    expect(journal.drafts.values.single.start, at(630));
  });

  testWidgets('shift selection excludes folded records', (tester) async {
    await open(tester);
    final state = tester.state<TimelineState>(find.byType(Timeline));
    await tester.tapAt(point(tester, state, 630));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tapAt(point(tester, state, 810));
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(journal.selected, {'a', 'b'});
  });

  testWidgets('escape restores a folded drag without saving', (tester) async {
    await open(tester);
    final before = Map.of(journal.store.events);
    final state = tester.state<TimelineState>(find.byType(Timeline));
    final start = point(tester, state, 630);
    final drag = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await drag.moveBy(const Offset(35, 0));
    await tester.pumpAndSettle();
    expect(find.text('拖动时临时展开 · 松手后恢复折叠'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await drag.up();
    await tester.pumpAndSettle();
    expect(state.axis.isFolded, isTrue);
    expect(state.horizontal.offset, 0);
    expect(journal.store.events, before);
  });

  testWidgets('all hidden records have a clear empty state and recovery', (
    tester,
  ) async {
    await journal.store.replaceEvents({'sleep': journal.event('sleep')!});
    await open(tester);
    expect(find.text('当前没有可显示的事项，已隐藏 1 条记录。'), findsOneWidget);
    await tester.tap(find.text('显示全部事项'));
    await tester.pumpAndSettle();
    expect(find.text('显示：完整一天'), findsOneWidget);
    expect(find.byKey(const ValueKey('row-sleep')), findsOneWidget);
  });

  testWidgets(
    'an empty unclassified filter can reveal all records in either mode',
    (tester) async {
      await journal.store.replaceEvents({'free': journal.event('free')!});
      final appearance = await open(tester);
      for (final preset in JournalViewPreset.values) {
        await appearance.setJournalView(
          JournalViewPreferences(preset: preset, showUnclassified: false),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('row-free')), findsNothing);
        expect(find.text('当前没有可显示的事项，已隐藏 1 条记录。'), findsOneWidget);
        await tester.tap(find.text('显示全部事项'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('row-free')), findsOneWidget);
        expect(appearance.state.journalView, JournalViewPreferences.fullDay);
      }
    },
  );
}
