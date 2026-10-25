import 'dart:io';
import 'dart:ui' as ui;

import 'package:daymark/application/appearance_controller.dart';
import 'package:daymark/application/journal_controller.dart';
import 'package:daymark/application/ledger_controller.dart';
import 'package:daymark/data/appearance_store.dart';
import 'package:daymark/data/ledger_store.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/appearance.dart';
import 'package:daymark/domain/model.dart';
import 'package:daymark/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/screenshot_fonts.dart';

void main() {
  testWidgets('synthetic screenshots preserve the timeline in both views', (
    tester,
  ) async {
    final previousShadows = debugDisableShadows;
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = previousShadows);
    await loadScreenshotFonts(tester);
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = DateTime.utc(2026, 10, 24);
    DateTime at(int minute) => day.add(Duration(minutes: minute));
    late Directory directory;
    late Store store;
    late AppearanceStore appearanceStore;
    late LedgerStore ledgerStore;
    await tester.runAsync(() async {
      directory = await (await Directory(
        '.test-artifacts',
      ).create(recursive: true)).createTemp('focus-screenshot-');
      store = await Store.open(directory, writer: (_, _) async {});
      await store.replaceTags({
        for (final tag in const [
          Tag('work', '主业', null),
          Tag('career', '职业探索', 'work'),
          Tag('thinking', 'Thinking', null),
          Tag('daymark', 'Daymark', 'thinking'),
          Tag('agent', 'ai agent', 'thinking'),
          Tag('chore', 'chore', null),
          Tag('life', '生活', null),
          Tag('sleep', '睡觉', 'life'),
          Tag('meal', '煮饭与用餐', 'life'),
          Tag('exercise', '运动', 'life'),
        ])
          tag.id: tag,
      });
      await store.replaceEvents({
        for (final event in [
          Event('sleep', '睡觉', 'sleep', at(0), at(510)),
          Event('breakfast', '早餐、买菜', 'meal', at(510), at(540)),
          Event('career', '梳理目标公司与岗位要求', 'career', at(540), at(630)),
          Event('chore', '整理笔记与自动下载', 'chore', at(660), at(700)),
          Event('lunch', '煮饭、午餐', 'meal', at(720), at(780)),
          Event('daymark', '改进时间轴的关注视图', 'daymark', at(780), at(870)),
          Event('agent', '验证工具调用与任务编排', 'agent', at(900), at(975)),
          Event('exercise', '户外步行', 'exercise', at(1020), at(1080)),
          Event('work', '上班', 'work', at(1080), at(1200)),
          Event('daymark2', '整理界面反馈', 'daymark', at(1230), at(1275)),
          Event('sleep2', '睡觉', 'sleep', at(1350), at(1920)),
        ])
          event.id: event,
      });
      appearanceStore = await AppearanceStore.open(
        directory,
        writer: (_, _) async {},
      );
      ledgerStore = await LedgerStore.open(directory, writer: (_, _) async {});
    });
    addTearDown(() => directory.delete(recursive: true));
    final journal = JournalController(store, day: day, clock: () => at(1500));
    final appearance = AppearanceController(appearanceStore);
    final ledger = LedgerController(ledgerStore, clock: () => at(1500));
    addTearDown(journal.dispose);
    addTearDown(appearance.dispose);
    addTearDown(ledger.dispose);
    await journal.initialize();
    await appearance.setTagStyle('work', TagColor.blue, TagDisplay.routine);
    await appearance.setTagStyle('life', TagColor.orange, TagDisplay.routine);
    await appearance.setTagStyle('career', TagColor.blue, TagDisplay.normal);
    await appearance.setTagStyle('chore', TagColor.pink, TagDisplay.normal);
    await appearance.setTagStyle('daymark', TagColor.teal, TagDisplay.normal);
    await appearance.setTagStyle('agent', TagColor.purple, TagDisplay.normal);
    await appearance.setTagStyle(
      'exercise',
      TagColor.orange,
      TagDisplay.normal,
    );
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: DaymarkApp(
          journal: journal,
          ledger: ledger,
          appearance: appearance,
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> screenshot(String name) async {
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
          '.test-artifacts/$name.png',
        ).writeAsBytes(bytes.buffer.asUint8List()),
      );
      image.dispose();
    }

    await screenshot('journal-focused');
    expect(find.byKey(const ValueKey('row-sleep')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('journal-display')));
    await tester.pumpAndSettle();
    await screenshot('journal-display-menu');
    await tester.tap(find.byKey(const ValueKey('view-full-day')));
    await tester.pumpAndSettle();
    await screenshot('journal-full-day');
    expect(find.byKey(const ValueKey('row-sleep')), findsOneWidget);
    debugDisableShadows = previousShadows;
    expect(tester.takeException(), isNull);
  });
}
