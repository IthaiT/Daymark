import 'support/screenshot_fonts.dart';
import 'package:daymark/ui/tag_visual.dart';
import 'package:daymark/ui/workspace_style.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:daymark/application/journal_controller.dart';
import 'package:daymark/data/atomic_file.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/event_clipboard.dart';
import 'package:daymark/domain/event_summary.dart';
import 'package:daymark/domain/model.dart';
import 'package:daymark/main.dart';
import 'package:daymark/ui/event_table.dart';
import 'package:daymark/ui/pickers.dart';
import 'package:daymark/ui/startup_window.dart';
import 'package:daymark/ui/tag_sidebar.dart';
import 'package:daymark/ui/timeline.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late JournalController journal;
  var failWrites = false;
  final day = DateTime.utc(2026, 10, 7);
  setUp(() async {
    directory = await (await Directory(
      '.test-artifacts',
    ).create()).createTemp('widgets-');
    var initializing = true;
    failWrites = false;
    final store = await Store.open(
      directory,
      writer: (file, bytes) async {
        if (failWrites) throw const FileSystemException('模拟写入失败');
        // UI interaction tests use immediate writes; real IO is covered by store tests.
        if (initializing) await AtomicFile.write(file, bytes);
      },
    );
    initializing = false;
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
        day.add(const Duration(hours: 13)),
        day.add(const Duration(hours: 14)),
      ),
    });
    journal = JournalController(
      store,
      day: day,
      clock: () => day.add(const Duration(hours: 16)),
    );
    await journal.initialize();
  });
  tearDown(() async {
    journal.dispose();
    await directory.delete(recursive: true);
  });
  Future<void> open(WidgetTester tester, {bool grouped = false}) async {
    final store = journal.store;
    journal.dispose();
    // Construct the asynchronous queue inside the Widget binding's clock zone.
    journal = JournalController(
      store,
      day: day,
      clock: () => day.add(const Duration(hours: 16)),
    );
    await journal.initialize();
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(DaymarkApp(journal: journal));
    await tester.pumpAndSettle();
    if (grouped) {
      await tester.tap(find.text('汇总'));
      await tester.pumpAndSettle();
    }
  }

  Finder cell(String id, String column) =>
      find.byKey(ValueKey('cell-$id-$column'));
  Finder input(String id, String column) =>
      find.byKey(ValueKey('input-$id-$column'));
  Future<void> key(
    WidgetTester tester,
    LogicalKeyboardKey value, {
    bool control = false,
    bool shift = false,
  }) async {
    if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    if (value == LogicalKeyboardKey.enter &&
        tester.testTextInput.hasAnyClients) {
      await tester.testTextInput.receiveAction(TextInputAction.done);
    } else {
      await tester.sendKeyEvent(value);
    }
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  String? clipboardText;
  void mockClipboard() {
    clipboardText = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          clipboardText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
          return null;
        case 'Clipboard.getData':
          return clipboardText == null ? null : {'text': clipboardText};
        case 'Clipboard.hasStrings':
          return {'value': clipboardText?.isNotEmpty ?? false};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
  }

  Finder group(String tagId) {
    final EventGroupKey groupKey = (tagId: tagId, draftId: null);
    return find.byKey(ValueKey(('event-group', groupKey)));
  }

  Future<String> seedSummary() async {
    final tag = await journal.store.saveTag('Daymark', 'explore');
    Event work(String id, int start, int end) => Event(
      id,
      'Daymark',
      tag.id,
      day.add(Duration(minutes: start)),
      day.add(Duration(minutes: end)),
    );
    final events = [
      Event(
        'different',
        'Daymark开发',
        tag.id,
        day.subtract(const Duration(hours: 2)),
        day.add(const Duration(minutes: 10)),
      ),
      Event(
        'sleep',
        '睡觉',
        'rest',
        day.add(const Duration(minutes: 56)),
        day.add(const Duration(minutes: 612)),
      ),
      work('work-a', 690, 750),
      work('work-b', 870, 960),
      work('work-c', 1020, 1080),
      work('work-d', 1200, 1380),
      Event(
        'unclassified',
        '吃饭 看番',
        null,
        day.add(const Duration(minutes: 750)),
        day.add(const Duration(minutes: 870)),
      ),
    ];
    final gaps = undefinedEvents(events).map(
      (event) =>
          event.copyWith(title: event.start.hour == 10 ? '赖床' : event.title),
    );
    await journal.store.replaceEvents({
      for (final event in [...events, ...gaps]) event.id: event,
    });
    return tag.id;
  }

  testWidgets(
    'summary groups tags across different names and keeps single-event clipboard',
    (tester) async {
      mockClipboard();
      final tagId = await seedSummary();
      await open(tester, grouped: true);
      final workGroup = group(tagId);
      expect(
        find.descendant(of: workGroup, matching: find.text('6 小时 40 分')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: workGroup, matching: find.text('5 条')),
        findsOneWidget,
      );
      expect(cell('work-a', 'title'), findsNothing);
      expect(cell('different', 'title'), findsNothing);
      final bucket = find.byKey(const ValueKey('group-unclassified'));
      expect(
        tester.getTopLeft(bucket).dy,
        greaterThan(tester.getTopLeft(workGroup).dy),
      );
      await tester.tap(bucket);
      await tester.pumpAndSettle();
      expect(cell('unclassified', 'title'), findsOneWidget);
      expect(find.text('赖床'), findsWidgets);
      await tester.tap(bucket);
      await tester.pumpAndSettle();
      await tester.tap(workGroup);
      await tester.pumpAndSettle();
      expect(journal.selected, isEmpty);
      expect(
        find.descendant(
          of: cell('different', 'title'),
          matching: find.text('Daymark开发'),
        ),
        findsOneWidget,
      );
      await tester.tap(cell('work-a', 'title'));
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.keyC, control: true);
      final copied = EventClipboard.tryDecode(clipboardText)!;
      expect(copied.events.length, 1);
      expect(copied.events.single.start, day.add(const Duration(minutes: 690)));
      await tester.tap(workGroup);
      await tester.pumpAndSettle();
      expect(cell('work-a', 'title'), findsNothing);
      expect(journal.selected, {'work-a'});
      await key(tester, LogicalKeyboardKey.keyC, control: true);
      expect(EventClipboard.tryDecode(clipboardText)!.events.length, 1);
      await key(tester, LogicalKeyboardKey.keyV, control: true);
      expect(
        journal.visibleEvents.where((event) => event.title == 'Daymark').length,
        5,
      );
      expect(
        find.descendant(of: workGroup, matching: find.text('6 小时 40 分')),
        findsOneWidget,
      );
      expect(cell(journal.selected.single, 'title'), findsOneWidget);
      await key(tester, LogicalKeyboardKey.keyZ, control: true);
      expect(
        journal.visibleEvents.where((event) => event.title == 'Daymark').length,
        4,
      );
      await tester.tap(find.text('时间顺序'));
      await tester.pumpAndSettle();
      expect(workGroup, findsNothing);
      expect(cell('different', 'title'), findsOneWidget);
      await tester.tap(find.text('汇总'));
      await tester.pumpAndSettle();
      expect(workGroup, findsOneWidget);
    },
  );

  testWidgets(
    'tag summary keeps renamed records together and failed writes block mode changes',
    (tester) async {
      final tagId = await seedSummary();
      await open(tester, grouped: true);
      await tester.tap(group(tagId));
      await tester.pumpAndSettle();
      await tester.tap(cell('work-a', 'title'));
      await tester.pumpAndSettle();
      await tester.tap(cell('work-a', 'title'));
      await tester.pumpAndSettle();
      await tester.enterText(input('work-a', 'title'), 'Daymark设计');
      failWrites = true;
      await tester.tap(group(tagId));
      await tester.pumpAndSettle();
      expect(input('work-a', 'title'), findsOneWidget);
      expect(
        tester.widget<TextField>(input('work-a', 'title')).controller!.text,
        'Daymark设计',
      );
      await tester.tap(find.text('时间顺序'));
      await tester.pumpAndSettle();
      expect(group(tagId), findsOneWidget);
      expect(journal.store.events['work-a']!.title, 'Daymark');
      failWrites = false;
      await key(tester, LogicalKeyboardKey.enter);
      expect(journal.store.events['work-a']!.title, 'Daymark设计');
      expect(
        find.descendant(of: group(tagId), matching: find.text('6 小时 40 分')),
        findsOneWidget,
      );
      expect(cell('work-a', 'title'), findsOneWidget);
      await key(tester, LogicalKeyboardKey.keyZ, control: true);
      expect(journal.store.events['work-a']!.title, 'Daymark');
    },
  );

  testWidgets(
    'grouped Shift selection follows displayed children and context deletes one record',
    (tester) async {
      mockClipboard();
      final tagId = await seedSummary();
      await open(tester, grouped: true);
      await tester.tap(group(tagId));
      await tester.pumpAndSettle();
      await tester.tap(cell('work-a', 'title'));
      await tester.pumpAndSettle();
      tester
          .state<EventTableState>(find.byType(EventTable))
          .reveal('different');
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(cell('different', 'title'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(journal.selected, {'work-a', 'different'});
      await key(tester, LogicalKeyboardKey.keyC, control: true);
      expect(EventClipboard.tryDecode(clipboardText)!.events.length, 2);
      journal.clearSelection();
      tester.state<EventTableState>(find.byType(EventTable)).reveal('work-a');
      await tester.pumpAndSettle();
      await tester.tap(cell('work-a', 'title'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(journal.store.events.containsKey('work-a'), isFalse);
      expect(journal.store.events.containsKey('work-b'), isTrue);
      expect(
        find.descendant(of: group(tagId), matching: find.text('5 小时 40 分')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'timeline selection expands its group and new blank drafts stay separate',
    (tester) async {
      final tagId = await seedSummary();
      await open(tester, grouped: true);
      final rectangle = tester.getRect(find.byType(Timeline));
      await tester.tapAt(
        Offset(
          rectangle.left + 24 + (rectangle.width - 50) * 11.75 / 24,
          rectangle.top + 80,
        ),
      );
      await tester.pumpAndSettle();
      expect(journal.selected, {'work-a'});
      expect(cell('work-a', 'title'), findsOneWidget);
      await tester.tap(group(tagId));
      await tester.pumpAndSettle();
      expect(cell('work-a', 'title'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('add-event')));
      await tester.pumpAndSettle();
      final first = journal.drafts.keys.single;
      expect(input(first, 'title'), findsOneWidget);
      await key(tester, LogicalKeyboardKey.keyN, control: true);
      final second = journal.drafts.keys.last;
      expect(journal.drafts.length, 2);
      expect(input(second, 'title'), findsOneWidget);
      expect(cell(first, 'title'), findsOneWidget);
    },
  );

  testWidgets(
    'table multi-selection copies and pastes onto another date with undo',
    (tester) async {
      mockClipboard();
      await open(tester);
      // Selecting a row must move focus away from the date's text field.
      await tester.tap(find.byKey(const ValueKey('day-input')));
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.escape);
      await tester.tap(cell('a', 'title'));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(cell('b', 'title'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.keyC, control: true);
      expect(EventClipboard.tryDecode(clipboardText)!.events.length, 2);
      await key(tester, LogicalKeyboardKey.arrowRight, control: true);
      await key(tester, LogicalKeyboardKey.keyV, control: true);
      final pasted = journal.visibleEvents;
      expect(pasted.length, 2);
      expect(pasted.map((event) => event.title).toSet(), {'做饭', '听播客'});
      expect(
        pasted.every(
          (event) => event.start == day.add(const Duration(days: 1, hours: 13)),
        ),
        isTrue,
      );
      expect(journal.selected.length, 2);
      await key(tester, LogicalKeyboardKey.keyZ, control: true);
      expect(journal.visibleEvents, isEmpty);
      await key(tester, LogicalKeyboardKey.keyY, control: true);
      expect(journal.visibleEvents.length, 2);
    },
  );

  testWidgets(
    'timeline copy and paste retains selection and retries failed writes',
    (tester) async {
      mockClipboard();
      await open(tester);
      final rectangle = tester.getRect(find.byType(Timeline));
      await tester.tapAt(
        Offset(
          rectangle.left + 24 + (rectangle.width - 50) * 14.5 / 24,
          rectangle.top + 80,
        ),
      );
      await tester.pumpAndSettle();
      expect(journal.selected, {'a'});
      await key(tester, LogicalKeyboardKey.keyC, control: true);
      failWrites = true;
      await key(tester, LogicalKeyboardKey.keyV, control: true);
      expect(find.text('操作未完成'), findsOneWidget);
      expect(journal.visibleEvents.length, 2);
      expect(journal.selected, {'a'});
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      failWrites = false;
      await key(tester, LogicalKeyboardKey.keyV, control: true);
      expect(journal.visibleEvents.length, 3);
      expect(journal.selected.length, 1);
      expect(journal.event(journal.selected.single)!.title, '做饭');
    },
  );

  testWidgets(
    'text fields keep native copy and paste and unrelated text creates no events',
    (tester) async {
      mockClipboard();
      await open(tester);
      clipboardText = '普通文字';
      await key(tester, LogicalKeyboardKey.keyV, control: true);
      expect(journal.visibleEvents.length, 2);
      clipboardText = 'Daymark events 1\n{}';
      await key(tester, LogicalKeyboardKey.keyV, control: true);
      expect(find.text('操作未完成'), findsOneWidget);
      expect(journal.visibleEvents.length, 2);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      await tester.tap(cell('a', 'title'));
      await tester.pumpAndSettle();
      await tester.tap(cell('a', 'title'));
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.keyC, control: true);
      expect(clipboardText, '做饭');
      clipboardText = '新名称';
      await key(tester, LogicalKeyboardKey.keyV, control: true);
      expect(
        tester.widget<TextField>(input('a', 'title')).controller!.text,
        '新名称',
      );
      expect(journal.visibleEvents.length, 2);
      await key(tester, LogicalKeyboardKey.enter);
      expect(journal.store.events['a']!.title, '新名称');
      await tester.tap(find.byKey(const ValueKey('day-input')));
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.escape);
      clipboardText = '2026-10-09';
      await key(tester, LogicalKeyboardKey.keyA, control: true);
      await key(tester, LogicalKeyboardKey.keyV, control: true);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('day-input')))
            .controller!
            .text,
        '2026-10-09',
      );
      expect(journal.visibleEvents.length, 2);
    },
  );

  testWidgets('tapping a parent row folds and unfolds its subtree', (
    tester,
  ) async {
    await open(tester);
    // The default tree nests embedded → linux under work.
    expect(find.byKey(const ValueKey('tag-work')), findsOneWidget);
    expect(find.byKey(const ValueKey('tag-embedded')), findsOneWidget);
    expect(find.byKey(const ValueKey('tag-linux')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tag-work')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tag-work')), findsOneWidget);
    expect(find.byKey(const ValueKey('tag-embedded')), findsNothing);
    expect(find.byKey(const ValueKey('tag-linux')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tag-work')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tag-embedded')), findsOneWidget);
    expect(find.byKey(const ValueKey('tag-linux')), findsOneWidget);
    // Collapsing a mid-level tag only hides its own descendants.
    await tester.tap(find.byKey(const ValueKey('tag-embedded')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tag-embedded')), findsOneWidget);
    expect(find.byKey(const ValueKey('tag-linux')), findsNothing);
    // Leaf rows keep the selection behavior instead of toggling.
    await tester.tap(find.byKey(const ValueKey('tag-embedded')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tag-linux')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tag-linux')), findsOneWidget);
  });

  testWidgets(
    'layout retains all panels, columns, Chinese controls and no tag filtering',
    (tester) async {
      await open(tester);
      for (final title in ['时间记录', '新增事件', '汇总', '时间顺序']) {
        expect(find.text(title), findsWidgets);
      }
      expect(find.byType(Timeline), findsOneWidget);
      final table = find.byType(EventTable);
      final viewSwitch = find.byType(AppSegmentedButton<EventTableMode>);
      expect(
        tester.widget<EventTable>(table).mode,
        EventTableMode.chronological,
      );
      expect(
        tester
            .widget<SegmentedButton<EventTableMode>>(viewSwitch)
            .segments
            .map((segment) => segment.value),
        [EventTableMode.chronological, EventTableMode.summary],
      );
      expect(
        tester.getCenter(find.text('时间顺序')).dx,
        lessThan(tester.getCenter(find.text('汇总')).dx),
      );
      for (final mode in [
        EventTableMode.summary,
        EventTableMode.chronological,
      ]) {
        for (final icon in [Icons.schedule, Icons.view_agenda_outlined]) {
          expect(
            find.descendant(of: viewSwitch, matching: find.byIcon(icon)),
            findsOneWidget,
          );
        }
        await tester.tap(
          find.text(mode == EventTableMode.summary ? '汇总' : '时间顺序'),
        );
        await tester.pumpAndSettle();
        expect(tester.widget<EventTable>(table).mode, mode);
      }
      for (final title in ['事件明细', '事件', '开始', '结束', '标签', '本日用时']) {
        expect(
          find.descendant(of: table, matching: find.text(title)),
          findsNothing,
        );
      }
      expect(
        tester.getCenter(find.byType(AppSegmentedButton<EventTableMode>)).dy,
        closeTo(
          tester.getCenter(find.byKey(const ValueKey('add-event'))).dy,
          .1,
        ),
      );
      expect(
        tester.getTopLeft(cell('a', 'title')).dy,
        closeTo(tester.getTopLeft(table).dy, .1),
      );
      await tester.tap(find.byKey(const ValueKey('tag-work')));
      await tester.pumpAndSettle();
      expect(cell('a', 'title'), findsOneWidget);
      expect(cell('b', 'title'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'smaller startup windows retain accessible panels and date controls',
    (tester) async {
      await open(tester);
      final sidebarState = tester.state(find.byType(TagSidebar));
      final timelineState = tester.state(find.byType(Timeline));
      for (final workArea in [
        const Rect.fromLTWH(0, 0, 1366, 728),
        const Rect.fromLTWH(0, 0, 1280, 680),
        const Rect.fromLTWH(0, 0, 960, 520),
        const Rect.fromLTWH(0, 0, 910, 485),
        const Rect.fromLTWH(0, 0, 800, 560),
        const Rect.fromLTWH(0, 0, 640, 336),
        const Rect.fromLTWH(0, 0, 455, 242),
      ]) {
        // The window size includes the native title bar and borders.
        final windowSize = startupWindowGeometry(workArea).bounds.size;
        tester.view.physicalSize = Size(
          windowSize.width - 16,
          windowSize.height - 40,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(Timeline), findsOneWidget);
        expect(tester.state(find.byType(TagSidebar)), same(sidebarState));
        expect(tester.state(find.byType(Timeline)), same(timelineState));
        for (final key in [
          'previous-day',
          'day-input',
          'next-day',
          'add-event',
        ]) {
          await tester.ensureVisible(find.byKey(ValueKey(key)));
          await tester.pumpAndSettle();
          expect(find.byKey(ValueKey(key)).hitTestable(), findsOneWidget);
        }
      }
    },
  );

  testWidgets(
    'first click selects, second edits, Enter saves and Escape cancels',
    (tester) async {
      await open(tester);
      await tester.tap(cell('a', 'title'));
      await tester.pumpAndSettle();
      expect(journal.selected, {'a'});
      expect(input('a', 'title'), findsNothing);
      await tester.tap(cell('a', 'title'));
      await tester.pumpAndSettle();
      expect(input('a', 'title'), findsOneWidget);
      await tester.enterText(input('a', 'title'), '新名称');
      await key(tester, LogicalKeyboardKey.enter);
      expect(journal.store.events['a']!.title, '新名称');
      await tester.tap(cell('a', 'title'));
      await tester.pumpAndSettle();
      await tester.enterText(input('a', 'title'), '取消的名称');
      await key(tester, LogicalKeyboardKey.escape);
      expect(journal.store.events['a']!.title, '新名称');
      expect(input('a', 'title'), findsNothing);
    },
  );

  testWidgets(
    'add and Ctrl+N create independent drafts, title Enter promotes, Esc discards current',
    (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('add-event')));
      await tester.pumpAndSettle();
      final first = journal.drafts.keys.single;
      await key(tester, LogicalKeyboardKey.keyN, control: true);
      expect(journal.drafts.length, 2);
      final second = journal.drafts.keys.last;
      expect(input(second, 'title'), findsOneWidget);
      await key(tester, LogicalKeyboardKey.escape);
      expect(journal.drafts.keys, [first]);
      await tester.tap(cell(first, 'title'));
      await tester.pumpAndSettle();
      await tester.tap(cell(first, 'title'));
      await tester.pumpAndSettle();
      await tester.enterText(input(first, 'title'), '保存草稿');
      await key(tester, LogicalKeyboardKey.enter);
      expect(journal.drafts, isEmpty);
      expect(journal.store.events[first]!.title, '保存草稿');
    },
  );

  testWidgets(
    'Tab saves and opens next cell, picker Escape returns typing focus',
    (tester) async {
      await open(tester);
      await tester.tap(cell('a', 'title'));
      await tester.pumpAndSettle();
      await tester.tap(cell('a', 'title'));
      await tester.pumpAndSettle();
      await tester.enterText(input('a', 'title'), 'Tab 保存');
      await key(tester, LogicalKeyboardKey.tab);
      expect(journal.store.events['a']!.title, 'Tab 保存');
      expect(input('a', 'start'), findsOneWidget);
      expect(find.byType(DateTimeChoices), findsOneWidget);
      await key(tester, LogicalKeyboardKey.escape);
      expect(find.byType(DateTimeChoices), findsNothing);
      await tester.enterText(input('a', 'start'), '12:00');
      await key(tester, LogicalKeyboardKey.enter);
      expect(journal.store.events['a']!.start.hour, 12);
    },
  );

  testWidgets(
    'invalid time and failed write preserve input and block row switching',
    (tester) async {
      await open(tester);
      await tester.tap(cell('a', 'start'));
      await tester.pumpAndSettle();
      await tester.tap(cell('a', 'start'));
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.escape);
      await tester.enterText(input('a', 'start'), '18:00');
      await tester.tap(cell('b', 'title'));
      await tester.pumpAndSettle();
      expect(input('a', 'start'), findsOneWidget);
      expect(journal.selected, {'a'});
      expect(journal.store.events['a']!.start.hour, 13);
      await tester.enterText(input('a', 'start'), '12:00');
      failWrites = true;
      await key(tester, LogicalKeyboardKey.enter);
      expect(input('a', 'start'), findsOneWidget);
      expect(journal.store.events['a']!.start.hour, 13);
      failWrites = false;
      await key(tester, LogicalKeyboardKey.enter);
      expect(journal.store.events['a']!.start.hour, 12);
    },
  );

  testWidgets('tag tree picker accepts parent and unclassified choices', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(cell('a', 'tag'));
    await tester.pumpAndSettle();
    await tester.tap(cell('a', 'tag'));
    await tester.pumpAndSettle();
    expect(find.byType(TagChoices), findsOneWidget);
    await tester.tap(
      find.descendant(of: find.byType(TagChoices), matching: find.text('主业')),
    );
    await tester.pumpAndSettle();
    expect(journal.store.events['a']!.tagId, 'work');
    expect(find.byType(TagChoices), findsNothing);
    await tester.tap(cell('a', 'tag'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(TagChoices), matching: find.text('未分类')),
    );
    await tester.pumpAndSettle();
    expect(journal.store.events['a']!.tagId, isNull);
  });

  testWidgets('tag picker shares sidebar styling and folds without choosing', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(cell('b', 'tag'));
    await tester.pumpAndSettle();
    await tester.tap(cell('b', 'tag'));
    await tester.pumpAndSettle();
    ListTile tile(String key) => tester.widget<ListTile>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(ListTile),
      ),
    );
    final sidebar = tile('tag-work');
    final picker = tile('tag-choice-work');
    expect(picker.selected, isTrue);
    expect(picker.selectedTileColor, sidebar.selectedTileColor);
    expect(picker.shape, sidebar.shape);
    expect(picker.contentPadding, sidebar.contentPadding);
    expect(
      tester
          .getSize(
            find.descendant(
              of: find.byKey(const ValueKey('tag-work')),
              matching: find.byType(ListTile),
            ),
          )
          .height,
      tester
          .getSize(
            find.descendant(
              of: find.byKey(const ValueKey('tag-choice-work')),
              matching: find.byType(ListTile),
            ),
          )
          .height,
    );
    final leftDot = sidebar.leading! as AppTagBadge;
    final pickerDot = picker.leading! as AppTagBadge;
    expect(pickerDot.family, leftDot.family);
    expect(pickerDot.accent, leftDot.accent);
    expect(pickerDot.size, leftDot.size);
    expect(
      tile('tag-choice-linux').contentPadding,
      tile('tag-linux').contentPadding,
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('tag-choice-work')),
        matching: find.byTooltip('收起主业'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tag-choice-linux')), findsNothing);
    expect(find.byType(TagChoices), findsOneWidget);
    expect(journal.store.events['b']!.tagId, 'work');
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('tag-choice-work')),
        matching: find.byTooltip('展开主业'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tag-choice-linux')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tag-choice-linux')));
    await tester.pumpAndSettle();
    expect(journal.store.events['b']!.tagId, 'linux');
    expect(find.byType(TagChoices), findsNothing);
  });

  testWidgets('new draft follows the last end and choosing a tag names it', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('add-event')));
    await tester.pumpAndSettle();
    final id = journal.drafts.keys.single;
    expect(journal.event(id)!.start, day.add(const Duration(hours: 15)));
    expect(journal.event(id)!.end, day.add(const Duration(hours: 16)));
    await key(tester, LogicalKeyboardKey.tab);
    await key(tester, LogicalKeyboardKey.tab);
    await key(tester, LogicalKeyboardKey.tab);
    expect(find.byType(TagChoices), findsOneWidget);
    failWrites = true;
    await tester.tap(
      find.descendant(of: find.byType(TagChoices), matching: find.text('主业')),
    );
    await tester.pumpAndSettle();
    expect(input(id, 'tag'), findsOneWidget);
    expect(journal.drafts[id]!.title, '');
    failWrites = false;
    await key(tester, LogicalKeyboardKey.enter);
    expect(journal.store.events[id]!.title, '主业');
    expect(journal.store.events[id]!.tagId, 'work');
    expect(journal.drafts, isEmpty);
    await key(tester, LogicalKeyboardKey.keyZ, control: true);
    expect(journal.drafts[id]!.title, '');
  });

  testWidgets(
    'Del deletes selected events and Ctrl+Z/Ctrl+Y restore and reapply',
    (tester) async {
      await open(tester);
      await tester.tap(cell('a', 'title'));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(cell('b', 'title'));
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(journal.selected, {'a', 'b'});
      await key(tester, LogicalKeyboardKey.delete);
      expect(journal.store.events, isEmpty);
      await key(tester, LogicalKeyboardKey.keyZ, control: true);
      expect(journal.store.events.containsKey('a'), isTrue);
      expect(journal.store.events.containsKey('b'), isTrue);
      await key(tester, LogicalKeyboardKey.keyY, control: true);
      expect(journal.store.events, isEmpty);
    },
  );

  testWidgets(
    'main calendar opens, Esc closes, arrows and date typing navigate',
    (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('day-input')));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDatePicker), findsOneWidget);
      await key(tester, LogicalKeyboardKey.escape);
      await tester.tap(find.byKey(const ValueKey('next-day')));
      await tester.pumpAndSettle();
      expect(journal.day, DateTime.utc(2026, 10, 8));
      await tester.enterText(
        find.byKey(const ValueKey('day-input')),
        '2026-10-09',
      );
      await key(tester, LogicalKeyboardKey.enter);
      expect(journal.day, DateTime.utc(2026, 10, 9));
    },
  );

  testWidgets(
    'cross-midnight gap is drawn and context-selectable on both days with daily duration',
    (tester) async {
      final tomorrow = day.add(const Duration(days: 1));
      final video = Event(
        'video',
        '视频',
        'life',
        day.add(const Duration(hours: 22)),
        day.add(const Duration(hours: 23, minutes: 50)),
      );
      final sleep = Event(
        'sleep',
        '睡觉',
        'rest',
        tomorrow.add(const Duration(minutes: 6)),
        tomorrow.add(const Duration(hours: 8)),
      );
      await journal.store.replaceEvents({video.id: video, sleep.id: sleep});
      await open(tester);
      final gap = journal.rows.singleWhere(
        (row) => row.isUndefined && row.start == video.end,
      );
      expect(
        find.descendant(
          of: cell(gap.id, 'duration'),
          matching: find.text('10 分钟'),
        ),
        findsOneWidget,
      );
      Future<void> clickMinute(double minute) async {
        final rectangle = tester.getRect(find.byType(Timeline));
        // These tiny gaps sit inside neighboring resize handles at 1x zoom;
        // the context click targets the rendered gap instead of a drag handle.
        await tester.tapAt(
          Offset(
            rectangle.left + 24 + (rectangle.width - 50) * minute / 1440,
            rectangle.top + 80,
          ),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        expect(find.text('设置标签'), findsOneWidget);
        await key(tester, LogicalKeyboardKey.escape);
      }

      await clickMinute(1435);
      expect(journal.selected, {gap.id});
      await key(tester, LogicalKeyboardKey.arrowRight, control: true);
      expect(journal.rows.where((row) => row.isUndefined), [gap]);
      expect(
        find.descendant(
          of: cell(gap.id, 'duration'),
          matching: find.text('6 分钟'),
        ),
        findsOneWidget,
      );
      await clickMinute(3);
      expect(journal.selected, {gap.id});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'timeline single click stays selected after double tap timeout and clock repaint',
    (tester) async {
      await open(tester);
      final timeline = tester.getRect(find.byType(Timeline));
      final width = timeline.width - 50;
      final point = Offset(
        timeline.left + 24 + width * 13.5 / 24,
        timeline.top + 80,
      );
      final before = journal.store.events;
      final gesture = await tester.startGesture(
        point,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
      expect(journal.selected, {'a'});
      await tester.pump(const Duration(minutes: 1));
      expect(journal.selected, {'a'});
      expect(journal.store.events, before);
      final row = tester.widget<ColoredBox>(
        find
            .descendant(
              of: find.byKey(const ValueKey('row-a')),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(
        row.color,
        tester
            .widget<MaterialApp>(find.byType(MaterialApp))
            .theme!
            .colorScheme
            .secondaryContainer,
      );
      final blank = await tester.startGesture(
        Offset(timeline.left + 24 + width * 20 / 24, timeline.top + 80),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await blank.up();
      await tester.pumpAndSettle();
      expect(journal.selected, isEmpty);
    },
  );

  testWidgets(
    'timeline click selects, body drag previews then commits and clears selection',
    (tester) async {
      await open(tester);
      final timeline = tester.getRect(find.byType(Timeline));
      final width = timeline.width - 50;
      final point = Offset(
        timeline.left + 24 + width * 13.5 / 24,
        timeline.top + 80,
      );
      final gesture = await tester.startGesture(
        point,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(journal.selected, {'a'});
      await gesture.moveBy(Offset(width / 24, 0));
      await tester.pump();
      expect(journal.store.events['a']!.start.hour, 13);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(journal.store.events['a']!.start.hour, 14);
      expect(journal.store.events['a']!.end!.hour, 16);
      expect(journal.selected, isEmpty);
    },
  );

  testWidgets(
    'right click keeps multiselection, deletes without confirmation and opens details',
    (tester) async {
      await open(tester);
      await tester.tap(cell('a', 'title'));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(cell('b', 'title'));
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(cell('a', 'title'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(journal.selected, {'a', 'b'});
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(journal.store.events, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
      await key(tester, LogicalKeyboardKey.keyZ, control: true);
      await tester.tap(cell('a', 'title'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑详情'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      final notes = find.widgetWithText(TextField, '备注');
      await tester.enterText(notes, '备注第一行\n第二行');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(journal.store.events['a']!.notes, '备注第一行\n第二行');
    },
  );

  testWidgets(
    'blank click saves, same row switches cell and another row selects before editing',
    (tester) async {
      await open(tester);
      await tester.tap(cell('a', 'title'));
      await tester.pumpAndSettle();
      await tester.tap(cell('a', 'title'));
      await tester.pumpAndSettle();
      await tester.enterText(input('a', 'title'), '先保存');
      await tester.tap(cell('a', 'tag'));
      await tester.pumpAndSettle();
      expect(journal.store.events['a']!.title, '先保存');
      expect(find.byType(TagChoices), findsOneWidget);
      await tester.tap(cell('b', 'title'));
      await tester.pumpAndSettle();
      expect(journal.selected, {'b'});
      expect(input('b', 'title'), findsNothing);
      await tester.tap(cell('b', 'title'));
      await tester.pumpAndSettle();
      await tester.enterText(input('b', 'title'), '空白保存');
      // The sidebar logo is always visible; its primary tap falls through to
      // the screen's blank-area handler, which commits and clears selection.
      await tester.tap(find.text('时间记录'));
      await tester.pumpAndSettle();
      expect(journal.store.events['b']!.title, '空白保存');
      expect(journal.selected, isEmpty);
    },
  );

  testWidgets(
    'nested date and hour-minute picker stays open, confirms complete timestamp',
    (tester) async {
      await open(tester);
      await tester.tap(cell('a', 'start'));
      await tester.pumpAndSettle();
      await tester.tap(cell('a', 'start'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextField, '日期'));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDatePicker), findsOneWidget);
      await tester.tap(
        find
            .descendant(
              of: find.byType(CalendarDatePicker),
              matching: find.text('6'),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(DateTimeChoices), findsOneWidget);
      await tester.tap(find.widgetWithText(TextField, '日期'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CalendarChoices>(find.byType(CalendarChoices)).value.day,
        6,
      );
      await tester.tap(
        find
            .descendant(
              of: find.byType(CalendarDatePicker),
              matching: find.text('6'),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextField, '时间'));
      await tester.pumpAndSettle();
      expect(find.byType(TimeChoices), findsOneWidget);
      await tester.tap(
        find
            .descendant(of: find.byType(TimeChoices), matching: find.text('14'))
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(TimeChoices),
          matching: find.text('确定'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextField, '时间'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TimeChoices>(find.byType(TimeChoices)).value.hour,
        14,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(TimeChoices),
          matching: find.text('确定'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DateTimeChoices),
          matching: find.text('确定'),
        ),
      );
      await tester.pumpAndSettle();
      expect(journal.store.events['a']!.start, DateTime.utc(2026, 10, 6, 14));
    },
  );

  testWidgets(
    'the first overnight sleep has no undefined row or timeline block before it',
    (tester) async {
      final sleep = Event(
        'sleep',
        '睡觉',
        'rest',
        day.add(const Duration(hours: 23, minutes: 49)),
        day.add(const Duration(days: 1, hours: 7, minutes: 40)),
      );
      final oldHead = Event(
        undefinedHeadId(day),
        '未定义',
        null,
        day,
        sleep.start,
      );
      await journal.store.replaceEvents({sleep.id: sleep, oldHead.id: oldHead});
      await open(tester);
      expect(journal.rows, [sleep]);
      expect(find.text('未定义'), findsNothing);
      final rect = tester.getRect(find.byType(Timeline));
      await tester.tapAt(Offset(rect.left + 80, rect.top + 100));
      await tester.pumpAndSettle();
      expect(journal.selected, isEmpty);
      expect(journal.store.events, {sleep.id: sleep});
    },
  );

  testWidgets(
    'gap time cells stay derived and tag assignment promotes renamed gap',
    (tester) async {
      await journal.store.saveEvent(
        Event(
          'later',
          '晚饭',
          'life',
          day.add(const Duration(hours: 18)),
          day.add(const Duration(hours: 19)),
        ),
      );
      await open(tester);
      final gap = journal.rows.firstWhere((event) => event.isUndefined);
      await tester.tap(cell(gap.id, 'start'));
      await tester.pumpAndSettle();
      await tester.tap(cell(gap.id, 'start'));
      await tester.pumpAndSettle();
      expect(input(gap.id, 'start'), findsNothing);
      await tester.tap(cell(gap.id, 'title'));
      await tester.pumpAndSettle();
      await tester.enterText(input(gap.id, 'title'), '睡觉');
      await key(tester, LogicalKeyboardKey.enter);
      expect(journal.event(gap.id)!.isUndefined, isTrue);
      await tester.tap(cell(gap.id, 'title'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.text('设置标签'), findsOneWidget);
      expect(find.text('删除'), findsNothing);
      await tester.tap(find.text('设置标签'));
      await tester.pumpAndSettle();
      final choice = find.descendant(
        of: find.byType(TagChoices),
        matching: find.text('生活'),
      );
      await tester.ensureVisible(choice);
      await tester.pumpAndSettle();
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(journal.event(gap.id), isNull);
      expect(
        journal.store.events.values
            .singleWhere((event) => event.title == '睡觉')
            .isUndefined,
        isFalse,
      );
    },
  );

  testWidgets(
    'timeline edges resize unselected event, Escape cancels and double click renames on canvas',
    (tester) async {
      await open(tester);
      final rect = tester.getRect(find.byType(Timeline));
      final width = rect.width - 50;
      final edge = Offset(rect.left + 24 + width * 15 / 24, rect.top + 100);
      final drag = await tester.startGesture(
        edge,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await drag.moveBy(Offset(width / 24, 0));
      await tester.pump();
      await key(tester, LogicalKeyboardKey.escape);
      await drag.up();
      await tester.pumpAndSettle();
      expect(journal.store.events['a']!.end!.hour, 15);
      final body = Offset(rect.left + 24 + width * 14.5 / 24, rect.top + 120);
      await tester.tapAt(body);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(body);
      await tester.pumpAndSettle();
      expect(input('a', 'title'), findsOneWidget);
      await tester.enterText(input('a', 'title'), '轨迹名称');
      await key(tester, LogicalKeyboardKey.enter);
      expect(journal.store.events['a']!.title, '轨迹名称');
      await tester.tapAt(Offset(rect.left + 30, rect.top + 20));
      await tester.pumpAndSettle();
      expect(journal.selected, isEmpty);
    },
  );

  testWidgets(
    'Ctrl wheel zooms around pointer, ordinary wheel scrolls and background context adds nearby',
    (tester) async {
      await open(tester);
      final rect = tester.getRect(find.byType(Timeline));
      final position = rect.center;
      final state = tester.state<TimelineState>(find.byType(Timeline));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      for (var i = 0; i < 20; i++) {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: position,
            scrollDelta: const Offset(0, -120),
          ),
        );
        await tester.pump();
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(state.zoom, 4);
      final offset = state.horizontal.offset;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: position,
          scrollDelta: const Offset(0, 120),
        ),
      );
      await tester.pump();
      expect(state.horizontal.offset, greaterThan(offset));
      await tester.tapAt(
        Offset(rect.left + 80, rect.top + 20),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('在此新增事件'));
      await tester.pumpAndSettle();
      expect(journal.drafts.length, 1);
    },
  );

  testWidgets(
    'tag context adds and edits, branch drag preserves IDs and descendant drop is rejected',
    (tester) async {
      await open(tester);
      await tester.tap(
        find.byKey(const ValueKey('tag-work')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('新增子标签'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '标签名称'), '迁移标签');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final tag = journal.store.tags.values.singleWhere(
        (tag) => tag.name == '迁移标签',
      );
      expect(tag.parentId, 'work');
      await tester.dragFrom(
        tester.getCenter(find.byKey(ValueKey('tag-${tag.id}'))),
        tester.getCenter(find.byKey(const ValueKey('tag-life'))) -
            tester.getCenter(find.byKey(ValueKey('tag-${tag.id}'))),
      );
      await tester.pumpAndSettle();
      expect(journal.store.tags[tag.id]!.parentId, 'life');
      final source = tester.getCenter(find.byKey(const ValueKey('tag-work')));
      final target = tester.getCenter(find.byKey(const ValueKey('tag-linux')));
      await tester.dragFrom(source, target - source);
      await tester.pumpAndSettle();
      expect(journal.store.tags['work']!.parentId, isNull);
      expect(journal.store.events['b']!.tagId, 'work');
    },
  );

  testWidgets(
    'renders a deterministic synthetic screenshot using system CJK and Material fonts',
    (tester) async {
      final previousShadows = debugDisableShadows;
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = previousShadows);
      await loadScreenshotFonts(tester);
      await open(tester);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: DaymarkApp(journal: journal),
        ),
      );
      await tester.pumpAndSettle();
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = (await tester.runAsync(
        () => boundary.toImage(pixelRatio: 1),
      ))!;
      final bytes = await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.png),
      );
      await tester.runAsync(
        () => File(
          '.test-artifacts/flutter-daymark.png',
        ).writeAsBytes(bytes!.buffer.asUint8List()),
      );
      image.dispose();
      await tester.tap(cell('b', 'tag'));
      await tester.pumpAndSettle();
      await tester.tap(cell('b', 'tag'));
      await tester.pumpAndSettle();
      final pickerImage = (await tester.runAsync(
        () => boundary.toImage(pixelRatio: 1),
      ))!;
      final pickerBytes = await tester.runAsync(
        () => pickerImage.toByteData(format: ui.ImageByteFormat.png),
      );
      await tester.runAsync(
        () => File(
          '.test-artifacts/flutter-tag-picker.png',
        ).writeAsBytes(pickerBytes!.buffer.asUint8List()),
      );
      pickerImage.dispose();
      await key(tester, LogicalKeyboardKey.escape);
      await key(tester, LogicalKeyboardKey.escape);
      final summaryTag = await seedSummary();
      await journal.initialize();
      await tester.pumpAndSettle();
      await tester.tap(find.text('汇总'));
      await tester.pumpAndSettle();
      for (final expanded in [false, true]) {
        if (expanded) {
          await tester.tap(group(summaryTag));
          await tester.pumpAndSettle();
        }
        final summaryImage = (await tester.runAsync(
          () => boundary.toImage(pixelRatio: 1),
        ))!;
        final summaryBytes = await tester.runAsync(
          () => summaryImage.toByteData(format: ui.ImageByteFormat.png),
        );
        await tester.runAsync(
          () => File(
            expanded
                ? '.test-artifacts/flutter-event-summary-expanded.png'
                : '.test-artifacts/flutter-event-summary.png',
          ).writeAsBytes(summaryBytes!.buffer.asUint8List()),
        );
        summaryImage.dispose();
      }
      debugDisableShadows = previousShadows;
      expect(tester.takeException(), isNull);
    },
  );
}
