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
import 'package:daymark/ui/timeline.dart';
import 'package:flutter/material.dart';
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
      final item = tester.widget<PopupMenuItem<Object?>>(
        find.byKey(const ValueKey('view-undefined')),
      );
      expect(item.enabled, isFalse);
      expect(find.text('自动生成已关闭'), findsOneWidget);
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
}
