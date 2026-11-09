import 'dart:io';
import 'dart:ui' as ui;

import 'package:daymark/application/journal_controller.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/item.dart';
import 'package:daymark/domain/model.dart';
import 'package:daymark/ui/event_organizer.dart';
import 'package:daymark/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/screenshot_fonts.dart';

void main() {
  late Directory directory;
  late JournalController journal;
  var failWrites = false;
  final day = DateTime.utc(2024, 1, 5);

  setUp(() async {
    failWrites = false;
    directory = await Directory(
      '.test-artifacts',
    ).createTemp('organizer-widget-');
    final store = await Store.open(
      directory,
      writer: (_, _) async {
        if (failWrites) throw const FileSystemException('模拟写入失败');
      },
    );
    await store.saveItem(
      const Item(id: 'parent', name: '学习计划', tagIds: ['work']),
    );
    await store.saveItem(
      Item(
        id: 'done',
        name: '已完成课程',
        parentId: 'parent',
        status: ItemStatus.done,
        endedOn: day,
      ),
    );
    await store.saveItem(const Item(id: 'bare', name: '无标签事项'));
    await store.replaceEvents({
      'a': Event(
        'a',
        '内核调度',
        'linux',
        day.add(const Duration(hours: 23)),
        day.add(const Duration(days: 1, hours: 1)),
        '迁移备注',
      ),
      'b': Event(
        'b',
        '会议',
        ['work', 'life'],
        day.add(const Duration(days: 1)),
        day.add(const Duration(days: 1, hours: 1)),
      ),
      'c': Event('c', '待补全', 'linux', day.add(const Duration(days: 2)), null),
    });
    journal = JournalController(store, day: day);
  });

  tearDown(() async {
    journal.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1360, 900),
  }) async {
    final store = journal.store;
    journal.dispose();
    journal = JournalController(store, day: day, clock: () => day);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: daymarkTheme(),
        home: RepaintBoundary(
          key: const ValueKey('organizer-capture'),
          child: Scaffold(body: EventOrganizer(journal: journal)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> selectAllAndMove(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('organize-select-all')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('移动所选事件'));
    await tester.tap(find.byTooltip('移动所选事件'));
    await tester.pumpAndSettle();
    expect(find.text('移动 3 条事件'), findsOneWidget);
  }

  testWidgets('all history is available and changing scope clears selection', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('已选 0 / 3 条'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('organize-source-work')));
    await tester.pumpAndSettle();
    expect(find.text('已选 0 / 1 条'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('organize-descendants')));
    await tester.pumpAndSettle();
    expect(find.text('已选 0 / 3 条'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('organize-select-all')));
    await tester.pumpAndSettle();
    expect(find.text('已选 3 / 3 条'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('organize-event-search')),
      '迁移备注',
    );
    await tester.pumpAndSettle();
    expect(find.text('已选 0 / 1 条'), findsOneWidget);
    expect(find.text('内核调度'), findsOneWidget);
  });

  testWidgets('date filters include cross-midnight records and reset cleanly', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byTooltip('筛选日期'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    final inputs = find.descendant(
      of: find.byType(DateRangePickerDialog),
      matching: find.byType(TextField),
    );
    expect(inputs, findsNWidgets(2));
    await tester.enterText(inputs.at(0), '01/06/2024');
    await tester.enterText(inputs.at(1), '01/06/2024');
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(find.text('已选 0 / 2 条'), findsOneWidget);
    expect(find.text('内核调度'), findsOneWidget);
    expect(find.text('会议'), findsOneWidget);
    await tester.tap(find.byTooltip('清除日期筛选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 0 / 3 条'), findsOneWidget);
  });

  testWidgets('tag moves preserve records and can be undone and redone', (
    tester,
  ) async {
    await mount(tester);
    await selectAllAndMove(tester);
    await tester.enterText(
      find.byKey(const ValueKey('organize-target-search')),
      '生活',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('organize-target-life')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('确认移动'));
    await tester.pumpAndSettle();
    expect(journal.store.events['a']!.tagIds, ['life']);
    expect(journal.store.events['c']!.end, isNull);
    expect(journal.store.events['a']!.notes, '迁移备注');
    await tester.tap(find.byTooltip('撤销最近修改'));
    await tester.pumpAndSettle();
    expect(journal.store.events['a']!.tagIds, ['linux']);
    await tester.tap(find.byTooltip('重做最近修改'));
    await tester.pumpAndSettle();
    expect(journal.store.events['a']!.tagIds, ['life']);
  });

  testWidgets(
    'completed historical items inherit tags and retain target on failed save',
    (tester) async {
      await mount(tester);
      await selectAllAndMove(tester);
      await tester.tap(find.text('事项'));
      await tester.enterText(
        find.byKey(const ValueKey('organize-target-search')),
        '已完成',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('organize-target-done')));
      await tester.pumpAndSettle();
      expect(find.textContaining('继承标签：主业'), findsOneWidget);
      failWrites = true;
      await tester.tap(find.byTooltip('确认移动'));
      await tester.pumpAndSettle();
      expect(find.textContaining('模拟写入失败'), findsOneWidget);
      expect(journal.store.events['a']!.tagIds, ['linux']);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('organize-target-search')),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        '已完成',
      );
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('organize-target-done')),
            )
            .selected,
        isTrue,
      );
      failWrites = false;
      await tester.tap(find.byTooltip('确认移动'));
      await tester.pumpAndSettle();
      expect(journal.store.events['a']!.itemId, 'done');
      expect(journal.store.events['a']!.tagIds, ['work']);
    },
  );

  testWidgets('an item with no tags is a valid destination', (tester) async {
    await mount(tester);
    await selectAllAndMove(tester);
    await tester.tap(find.text('事项'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('organize-target-bare')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('确认移动'));
    await tester.pumpAndSettle();
    expect(journal.store.events['a']!.itemId, 'bare');
    expect(journal.store.events['a']!.tagIds, isEmpty);
  });

  testWidgets('cleanup previews unused branches and preserves used tags', (
    tester,
  ) async {
    final empty = await journal.store.saveTag('旧空标签', null);
    await mount(tester);
    await tester.tap(find.byTooltip('清理空标签'));
    await tester.pumpAndSettle();
    expect(find.textContaining('清空撤销记录'), findsOneWidget);
    expect(find.text('旧空标签'), findsWidgets);
    await tester.tap(find.byTooltip('确认删除空标签'));
    await tester.pumpAndSettle();
    expect(journal.store.tags, isNot(contains(empty.id)));
    expect(journal.store.tags, contains('linux'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow windows scroll without layout overflow', (tester) async {
    await mount(tester, size: const Size(820, 640));
    expect(tester.takeException(), isNull);
    await selectAllAndMove(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('synthetic screenshots use readable text and Material icons', (
    tester,
  ) async {
    await loadScreenshotFonts(tester);
    await mount(tester);
    Future<void> capture(RenderRepaintBoundary boundary, String name) async {
      await tester.runAsync(() async {
        final picture = await boundary.toImage();
        final bytes = (await picture.toByteData(
          format: ui.ImageByteFormat.png,
        ))!;
        await File(
          '.test-artifacts/$name.png',
        ).writeAsBytes(bytes.buffer.asUint8List());
        picture.dispose();
      });
    }

    await capture(
      tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('organizer-capture')),
      ),
      'event-organizer',
    );
    await selectAllAndMove(tester);
    await tester.tap(find.text('事项'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('organize-target-done')));
    await tester.pumpAndSettle();
    // The root overlay contains the target dialog, outside the home boundary.
    final root = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('organize-move-capture')),
    );
    await capture(root, 'event-organizer-target');
    expect(tester.takeException(), isNull);
  });
}
