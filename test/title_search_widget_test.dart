import 'dart:io';
import 'dart:ui' as ui;

import 'package:daymark/application/journal_controller.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/item.dart';
import 'package:daymark/domain/model.dart';
import 'package:daymark/ui/inline_editor.dart';
import 'package:daymark/ui/pickers.dart';
import 'package:daymark/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/screenshot_fonts.dart';

void main() {
  late Directory directory;
  late Store store;
  late EditSession session;
  final today = DateTime.utc(2026, 11, 8);
  const feature = '实现记录事项化的功能，并完整保留所有历史时间记录与事项之间的关联';
  const parse = '独立软件侧解析 Obsidian Markdown 内容，同时支持多层子事项与多个标签';
  setUp(() async {
    directory = await (await Directory(
      '.test-artifacts',
    ).create()).createTemp('title-search-');
    store = await Store.open(directory, clock: () => today);
    await store.saveItem(
      const Item(id: 'feat', name: 'feat', tagIds: ['work']),
    );
    await store.saveItem(
      const Item(id: 'feature', name: feature, parentId: 'feat'),
    );
    await store.saveItem(
      Item(
        id: 'parse',
        name: parse,
        parentId: 'feature',
        status: ItemStatus.done,
        completedOn: today,
        outcome: '完成',
        tagIds: ['side'],
      ),
    );
    session = EditSession(
      Event('draft', '', null, today, today.add(const Duration(hours: 1))),
      EventColumn.title,
    );
  });
  tearDown(() async {
    session.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> open(WidgetTester tester, {GlobalKey? boundary}) async {
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          theme: daymarkTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: 320,
                  child: InlineEditor(
                    session: session,
                    store: store,
                    day: today,
                    onCommit: () async => true,
                    onCompleteChoice: () {},
                    onCancel: () {},
                    onNext: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'feat');
    await tester.pumpAndSettle();
  }

  testWidgets(
    'path suggestions show bounded hierarchy, full tooltips and no leading icons',
    (tester) async {
      tester.view.physicalSize = const Size(460, 380);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (const bool.fromEnvironment('DAYMARK_CAPTURE_UI')) {
        await loadScreenshotFonts(tester);
      }
      final boundary = GlobalKey();
      await open(tester, boundary: boundary);
      final choices = find.byType(TitleChoices);
      expect(
        find.descendant(of: choices, matching: find.byType(Icon)),
        findsNothing,
      );
      for (final id in ['feat', 'feature', 'parse']) {
        final tile = tester.widget<ListTile>(
          find.byKey(ValueKey('title-choice-item-$id')),
        );
        expect(tile.leading, isNull);
        expect(
          tile.contentPadding,
          EdgeInsets.only(
            left: 12 + ['feat', 'feature', 'parse'].indexOf(id) * 12,
            right: 12,
          ),
        );
        expect((tile.title! as Text).maxLines, 1);
        expect((tile.title! as Text).overflow, TextOverflow.ellipsis);
      }
      expect(find.byTooltip('feat / $feature\n$parse'), findsOneWidget);
      expect(find.text('已完成'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('DAYMARK_CAPTURE_UI')) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '.test-artifacts/title-search.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.byKey(const ValueKey('title-choice-item-parse')));
      await tester.pumpAndSettle();
      expect(session.itemId, 'parse');
      expect(session.text.text, parse);
      expect(session.tagIds, ['work', 'side']);
      expect(store.items['parse']!.status, ItemStatus.done);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'keyboard navigation scrolls through all descendants and chooses the visible row',
    (tester) async {
      await tester.runAsync(() async {
        for (var index = 0; index < 18; index++) {
          await store.saveItem(
            Item(
              id: 'child-$index',
              name: '子事项${index.toString().padLeft(2, '0')}',
              parentId: 'feat',
            ),
          );
        }
      });
      await open(tester);
      for (var index = 0; index < 15; index++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      expect(session.titleIndex, 15);
      final choice = titleChoices(store, 'feat')[15];
      final row = find.byKey(ValueKey('title-choice-item-${choice.owner.id}'));
      expect(row.hitTestable(), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(session.itemId, choice.owner.id);
      expect(session.tagIds, ['work']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
