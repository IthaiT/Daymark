import 'dart:io';
import 'dart:ui' as ui;

import 'package:daymark/data/store.dart';
import 'package:daymark/domain/model.dart';
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
}
