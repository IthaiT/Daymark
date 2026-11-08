import 'dart:io';
import 'dart:ui' as ui;

import 'package:daymark/application/journal_controller.dart';
import 'package:daymark/application/ledger_controller.dart';
import 'package:daymark/application/settings_controller.dart';
import 'package:daymark/data/ledger_store.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/model.dart';
import 'package:daymark/domain/obsidian.dart';
import 'package:daymark/ui/app_screen.dart';
import 'package:daymark/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/screenshot_fonts.dart';

void main() {
  late Directory directory;
  late Store store;
  late LedgerController ledger;
  const folder = 'synthetic/Daymark';
  final day = DateTime.utc(2026, 11, 8);

  setUp(() async {
    directory = await (await Directory(
      '.test-artifacts',
    ).create()).createTemp('obsidian-deletion-widget-');
    store = await Store.open(directory, writer: (_, _) async {});
    ledger = LedgerController(
      await LedgerStore.open(directory, writer: (_, _) async {}),
    );
    await store.importObsidian(
      parseObsidian({
        'A.md':
            '---\ndaymark-id: note-a\ntags: [主业]\n---\n- [ ] 有记录 | 实际描述 | 实际结果 ^daymark-task-a\n- [x] 无记录 ^daymark-task-b\n',
      }, directory: folder),
      directory: folder,
    );
    await store.saveEvent(
      Event(
        'e',
        '历史时间记录',
        'work',
        day.add(const Duration(hours: 9)),
        day.add(const Duration(hours: 10)),
        '原备注',
        'task-a',
      ),
    );
  });
  tearDown(() async {
    ledger.dispose();
    await directory.delete(recursive: true);
  });

  testWidgets(
    'deleted source references show a notice, open the item and clear after reassignment',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (const bool.fromEnvironment('DAYMARK_CAPTURE_UI')) {
        await loadScreenshotFonts(tester);
      }
      final journal = JournalController(store, day: day, clock: () => day);
      final settings = SettingsController();
      addTearDown(journal.dispose);
      addTearDown(settings.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: daymarkTheme(),
          home: RepaintBoundary(
            key: boundary,
            child: AppScreen(
              journal: journal,
              ledger: ledger,
              settings: settings,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('obsidian-deleted-notice')),
        findsNothing,
      );
      await store.importObsidian(
        parseObsidian({}, directory: folder),
        directory: folder,
      );
      await journal.applySettings(
        journal.settings.copyWith(splitOverlap: true),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Obsidian 中已删除 1 个事项，仍有 1 条时间记录引用，已保留关联。'),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('view-deleted-obsidian-item')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('project-deleted-source')),
        findsOneWidget,
      );
      expect(find.text('源已删除'), findsOneWidget);
      expect(find.text('实际描述'), findsOneWidget);
      expect(find.text('实际结果'), findsOneWidget);
      expect(find.byKey(const ValueKey('project-open-obsidian')), findsNothing);
      expect(find.byKey(const ValueKey('project-note-a')), findsNothing);
      expect(find.byKey(const ValueKey('project-task-b')), findsNothing);
      expect(store.events['e']!.itemId, 'task-a');
      if (const bool.fromEnvironment('DAYMARK_CAPTURE_UI')) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '.test-artifacts/obsidian-deleted-source.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await journal.setEventItem(['e'], null);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('obsidian-deleted-notice')),
        findsNothing,
      );
      await store.importObsidian(
        parseObsidian({}, directory: folder),
        directory: folder,
      );
      await journal.applySettings(
        journal.settings.copyWith(splitOverlap: false),
      );
      await tester.pumpAndSettle();
      expect(store.items, isEmpty);
      expect(store.events['e']!.title, '历史时间记录');
      expect(store.events['e']!.notes, '原备注');
      expect(
        find.byKey(const ValueKey('project-deleted-source')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
