import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:daymark/application/journal_controller.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/model.dart';
import 'package:daymark/ui/calendar_heatmap.dart';
import 'package:daymark/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/screenshot_fonts.dart';

void main() {
  late Directory directory;
  late Store store;
  JournalController? journal;
  final day = DateTime.utc(2026, 10, 24);

  setUp(() async {
    directory = await (await Directory(
      '.test-artifacts',
    ).create()).createTemp('heatmap-pixels-');
    store = await Store.open(directory, writer: (_, _) async {});
    await store.replaceEvents({
      'work': Event(
        'work',
        '工作',
        'work',
        DateTime.utc(2026, 10, 23, 8),
        DateTime.utc(2026, 10, 23, 20),
      ),
      'rest': Event(
        'rest',
        '休息',
        'rest',
        day.add(const Duration(hours: 8)),
        day.add(const Duration(hours: 10)),
      ),
    });
  });

  tearDown(() async {
    journal?.dispose();
    journal = null;
    await directory.delete(recursive: true);
  });

  Future<void> open(
    WidgetTester tester,
    double scale,
    GlobalKey boundary, {
    Size chart = const Size(1037.7, 400),
    Size view = const Size(1201, 701),
  }) async {
    journal?.dispose();
    final controller = JournalController(store, day: day);
    journal = controller;
    await controller.initialize();
    tester.view.devicePixelRatio = scale;
    tester.view.physicalSize = Size(
      (view.width * scale).roundToDouble(),
      (view.height * scale).roundToDouble(),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: daymarkTheme(),
          home: Scaffold(
            backgroundColor: Colors.white,
            body: Padding(
              padding: const EdgeInsets.only(left: 3.3, top: 7.7, right: 2.1),
              child: SizedBox(
                width: chart.width,
                height: chart.height,
                child: AnimatedBuilder(
                  animation: controller,
                  builder: (_, _) => CalendarHeatmap(
                    journal: controller,
                    selection: allActivityTags,
                    onSelectionChanged: (_) {},
                    onDaySelected: (day) => unawaited(controller.setDay(day)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectAligned(WidgetTester tester, Finder cell, double scale) {
    final rect = tester.getRect(cell);
    for (final value in [rect.left, rect.top, rect.width, rect.height]) {
      expect(
        value * scale,
        closeTo((value * scale).round(), .000001),
        reason: 'DPR $scale: $rect',
      );
    }
  }

  void expectColorClose(Color actual, Color expected, String reason) {
    // Allow byte-level raster rounding, not the blending of a half-pixel edge.
    for (final shift in [0, 8, 16, 24]) {
      expect(
        (actual.toARGB32() >> shift) & 255,
        closeTo((expected.toARGB32() >> shift) & 255, 3),
        reason: reason,
      );
    }
  }

  testWidgets(
    'day rectangles and rasterized straight edges align at every DPI',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await loadScreenshotFonts(tester);
      final boundary = GlobalKey();
      for (final scale in [1.0, 1.25, 1.5, 2.0]) {
        await open(tester, scale, boundary);
        final cells = [
          find.byKey(const ValueKey('activity-day-2026-10-23')),
          find.byKey(const ValueKey('activity-day-2026-10-24')),
        ];
        for (final cell in cells) {
          expectAligned(tester, cell, scale);
        }
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final picture = (await tester.runAsync(
          () => render.toImage(pixelRatio: scale),
        ))!;
        try {
          final bytes = (await tester.runAsync(
            () => picture.toByteData(format: ui.ImageByteFormat.rawRgba),
          ))!;
          Color pixel(int x, int y) {
            final offset = (y * picture.width + x) * 4;
            return Color.fromARGB(
              bytes.getUint8(offset + 3),
              bytes.getUint8(offset),
              bytes.getUint8(offset + 1),
              bytes.getUint8(offset + 2),
            );
          }

          for (final (index, cell) in cells.indexed) {
            final material = tester.widget<Material>(cell);
            final side = (material.shape! as RoundedRectangleBorder).side;
            final borderPixels = index == 0 ? 1 : 2;
            expect(side.width * scale, closeTo(borderPixels, .000001));
            final rect = tester.getRect(cell);
            final left = (rect.left * scale).round();
            final middle = (rect.center.dy * scale).floor();
            expectColorClose(
              pixel(left - 1, middle),
              Colors.white,
              'DPR $scale outside $rect',
            );
            expectColorClose(
              pixel(left, middle),
              side.color,
              'DPR $scale border $rect',
            );
            expect(
              pixel(left + borderPixels, middle).toARGB32(),
              material.color!.toARGB32(),
            );
          }
          await tester.runAsync(() async {
            final png = (await picture.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            await File(
              '.test-artifacts/heatmap-crisp-${(scale * 100).round()}.png',
            ).writeAsBytes(png.buffer.asUint8List());
          });
        } finally {
          picture.dispose();
        }
        await tester.tap(cells.first);
        await tester.pumpAndSettle();
        expect(journal!.day, DateTime.utc(2026, 10, 23));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('fractional scrolling preserves alignment and cell hit testing', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const scale = 1.25;
    await open(
      tester,
      scale,
      GlobalKey(),
      chart: const Size(500, 180),
      view: const Size(600, 300),
    );
    final views = tester.widgetList<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    views
        .singleWhere((view) => view.scrollDirection == Axis.horizontal)
        .controller!
        .jumpTo(2.3);
    views
        .singleWhere(
          (view) =>
              view.scrollDirection == Axis.vertical && view.controller != null,
        )
        .controller!
        .jumpTo(1.7);
    await tester.pumpAndSettle();
    final cell = find.byKey(const ValueKey('activity-day-2026-01-20'));
    expectAligned(tester, cell, scale);
    await tester.tap(cell);
    await tester.pumpAndSettle();
    expect(journal!.day, DateTime.utc(2026, 1, 20));
    expect(tester.takeException(), isNull);
  });
}
