import 'dart:io';
import 'dart:ui' as ui;

import 'package:daymark/data/store.dart';
import 'package:daymark/domain/model.dart';
import 'package:daymark/domain/item.dart';
import 'package:daymark/domain/appearance.dart';
import 'package:daymark/ui/tag_chips.dart';
import 'package:daymark/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/screenshot_fonts.dart';

void main() {
  late Directory directory;
  late Store store;
  setUp(() async {
    directory = await (await Directory(
      '.test-artifacts',
    ).create()).createTemp('tag-chips-');
    store = await Store.open(directory, writer: (_, _) async {});
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  testWidgets('independent tag colors and overflow menu retain every label', (
    tester,
  ) async {
    final boundary = GlobalKey();
    if (const bool.fromEnvironment('DAYMARK_CAPTURE_UI')) {
      await loadScreenshotFonts(tester);
    }
    final ids = ['work', 'side', 'explore', 'life'];
    final event = Event('chips', '事项', ids, DateTime.utc(2026, 11, 8), null);
    Future<void> show(double width) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: daymarkTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                height: 40,
                child: RepaintBoundary(
                  key: boundary,
                  child: RecordTagChips(store: store, event: event),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> capture(String name) async {
      if (!const bool.fromEnvironment('DAYMARK_CAPTURE_UI')) return;
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '.test-artifacts/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await show(700);
    await capture('record-tags');
    expect(find.byType(TagToken), findsNWidgets(4));
    expect(
      find.descendant(of: find.byType(TagToken), matching: find.byType(Icon)),
      findsNothing,
    );
    final work = tester.widget<TagToken>(
      find.byKey(const ValueKey('record-tag-chips-work')),
    );
    final side = tester.widget<TagToken>(
      find.byKey(const ValueKey('record-tag-chips-side')),
    );
    expect(work.background, isNot(side.background));
    await show(125);
    await capture('record-tags-overflow');
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('record-tags-overflow-chips')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('record-tags-overflow-chips')));
    await tester.pumpAndSettle();
    for (final id in ids) {
      expect(find.text(store.tagName(id)), findsWidgets);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'item badge stays distinct from tags and survives narrow columns',
    (tester) async {
      final boundary = GlobalKey();
      if (const bool.fromEnvironment('DAYMARK_CAPTURE_UI')) {
        await loadScreenshotFonts(tester);
      }
      await store.saveItem(const Item(id: 'root', name: '主业'));
      await store.saveItem(
        const Item(id: 'task', name: '推进方案', parentId: 'root'),
      );
      final event = Event(
        'owned',
        '推进方案',
        ['work', 'side', 'explore', 'life'],
        DateTime.utc(2026, 11, 8),
        null,
        '',
        'task',
      );
      Future<void> show(double width, {bool routine = false}) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: daymarkTheme(
              tagDisplays: routine ? {'work': TagDisplay.routine} : {},
            ),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  height: 40,
                  child: RepaintBoundary(
                    key: boundary,
                    child: RecordTagChips(store: store, event: event),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> capture(String name) async {
        if (!const bool.fromEnvironment('DAYMARK_CAPTURE_UI')) return;
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '.test-artifacts/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      BoxDecoration itemDecoration() =>
          tester
                  .widget<Container>(
                    find.descendant(
                      of: find.byType(RecordItemBadge),
                      matching: find.byType(Container),
                    ),
                  )
                  .decoration!
              as BoxDecoration;

      await show(700);
      await capture('record-owner-tags');
      expect(find.text('事项 · 主业'), findsOneWidget);
      expect(find.text('主业'), findsOneWidget);
      expect(find.byType(TagToken), findsNWidgets(4));
      expect(find.byTooltip('所属事项：主业'), findsOneWidget);
      final badge = itemDecoration();
      for (final token in tester.widgetList<TagToken>(find.byType(TagToken))) {
        expect(badge.color, isNot(token.background));
        expect(token.foreground, isNot(Colors.white));
      }
      expect(
        tester.widget<Text>(find.text('事项 · 主业')).style!.color,
        Colors.white,
      );
      await show(700, routine: true);
      expect(
        itemDecoration().color,
        isNot(
          tester
              .widget<TagToken>(
                find.byKey(const ValueKey('record-tag-owned-work')),
              )
              .background,
        ),
      );

      await store.saveItem(const Item(id: 'root', name: '工作计划与后续方案的持续推进'));
      await show(125);
      await capture('record-owner-tags-overflow');
      expect(find.byType(RecordItemBadge), findsOneWidget);
      expect(find.text('+4'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.byKey(const ValueKey('record-tags-overflow-owned')),
      );
      await tester.pumpAndSettle();
      for (final id in event.tagIds) {
        expect(find.text(store.tagName(id)), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(760, 560));
      await tester.pumpAndSettle();

      // Very narrow columns retain the distinction in the overflow menu as well.
      await show(50);
      expect(find.text('+5'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('record-tags-overflow-owned')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RecordItemBadge), findsOneWidget);
      expect(find.byType(TagToken), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    },
  );
}
