import 'dart:io';
import 'dart:ui' as ui;

import 'package:daymark/application/journal_controller.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/model.dart';
import 'package:daymark/domain/obsidian.dart';
import 'package:daymark/domain/settings.dart';
import 'package:daymark/ui/inline_editor.dart';
import 'package:daymark/ui/pickers.dart';
import 'package:daymark/ui/project_screen.dart';
import 'package:daymark/ui/settings_dialog.dart';
import 'package:daymark/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/screenshot_fonts.dart';

void main() {
  late Directory directory;
  late Store store;
  var counter = 0;
  const source =
      '---\ntags: [主业, 副业]\n---\n- [ ] 完成导入 | 解析 Obsidian 的事项 |\n  - [/] 等待确认 | 暂停事项\n- [-] 取消方案 | | 保留历史\n- [x] 验证原型 | | 测试通过\n';
  setUp(() async {
    directory = await (await Directory(
      '.test-artifacts',
    ).create()).createTemp('obsidian-widget-');
    store = await Store.open(directory, writer: (_, bytes) async {});
    await store.importObsidian(
      parseObsidian(
        {'工作计划.md': source},
        directory: 'synthetic/Daymark',
        newId: () => 'node-${counter++}',
      ),
      directory: 'synthetic/Daymark',
    );
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  testWidgets(
    'all states appear in the item page and refresh after another import',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (const bool.fromEnvironment('DAYMARK_CAPTURE_UI')) {
        await loadScreenshotFonts(tester);
      }
      final journal = JournalController(store);
      addTearDown(journal.dispose);
      final boundary = GlobalKey();
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: daymarkTheme(),
          home: Scaffold(
            body: RepaintBoundary(
              key: boundary,
              child: ProjectScreen(
                journal: journal,
                openNote: (directory, path) async {
                  expect(directory, 'synthetic/Daymark');
                  opened.add(path);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final task = store.items.values.singleWhere((n) => n.name == '完成导入');
      await tester.tap(find.byKey(ValueKey('project-${task.id}')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('project-imported-name')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('project-open-obsidian')),
        findsOneWidget,
      );
      expect(find.text('暂停'), findsOneWidget);
      expect(find.text('已完成'), findsOneWidget);
      expect(find.text('已取消'), findsOneWidget);
      expect(find.byKey(const ValueKey('item-source-status')), findsNothing);
      expect(find.byKey(const ValueKey('project-delete')), findsNothing);
      expect(find.byKey(const ValueKey('project-sync')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('project-open-obsidian')));
      await tester.pumpAndSettle();
      expect(opened, ['工作计划.md#^daymark-${task.id}']);
      if (const bool.fromEnvironment('DAYMARK_CAPTURE_UI')) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '.test-artifacts/obsidian-items.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      final annotated = store.items.values
          .singleWhere((n) => n.source!.kind == 'file')
          .source!
          .raw;
      await store.importObsidian(
        parseObsidian({
          '工作计划.md': annotated.replaceFirst('完成导入', '导入已更新'),
        }, directory: 'synthetic/Daymark'),
        directory: 'synthetic/Daymark',
      );
      await journal.backupTree();
      // Notifications use the same path as a real synchronization.
      await journal.applySettings(
        journal.settings.copyWith(splitOverlap: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('导入已更新'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'name choice fills inherited tags and tag choices accumulate independently',
    (tester) async {
      final task = store.items.values.singleWhere((n) => n.name == '完成导入');
      final day = DateTime.utc(2026, 11, 8);
      var session = EditSession(
        Event('draft', '', null, day, day.add(const Duration(hours: 1))),
        EventColumn.title,
      );
      Future<void> open() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: daymarkTheme(),
            home: Scaffold(
              body: SizedBox(
                width: 420,
                child: InlineEditor(
                  key: ValueKey(session.column),
                  session: session,
                  store: store,
                  day: day,
                  onCommit: () async => true,
                  onCompleteTag: () {},
                  onCancel: () {},
                  onNext: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await open();
      await tester.enterText(find.byType(TextField), '成导');
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('title-choice-item-${task.id}')),
        findsOneWidget,
      );
      expect(titleChoices(store, '主业'), isEmpty);
      await tester.tap(find.byKey(ValueKey('title-choice-item-${task.id}')));
      await tester.pumpAndSettle();
      expect(session.itemId, task.id);
      expect(session.tagIds, ['work', 'side']);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      session = EditSession(
        Event(
          'e',
          '自由记录',
          ['work'],
          day,
          day.add(const Duration(hours: 1)),
          '',
          task.id,
        ),
        EventColumn.tag,
      );
      await open();
      expect(find.byKey(ValueKey('owner-item-${task.id}')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('tag-choice-side')));
      await tester.pumpAndSettle();
      expect(session.tagIds, ['side', 'work']);
      expect(session.itemId, task.id);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tag-choice-work')));
      await tester.pumpAndSettle();
      expect(session.tagIds, ['side']);
      expect(session.itemId, task.id);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    },
  );

  testWidgets(
    'manual sync failure retains folder input and can retry before saving',
    (tester) async {
      var fail = true;
      AppSettings? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: daymarkTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showSettingsDialog(
                  context,
                  settings: const AppSettings(),
                  onSave: (value) async {
                    saved = value;
                  },
                  onSyncObsidian: (path) async {
                    expect(path, 'synthetic/Daymark');
                    if (fail) throw const FormatException('模拟同步失败');
                    return 5;
                  },
                ),
                child: const Text('打开设置'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开设置'));
      await tester.pumpAndSettle();
      final folder = find.byKey(const ValueKey('setting-obsidian-directory'));
      await tester.ensureVisible(folder);
      await tester.enterText(folder, 'synthetic/Daymark');
      final sync = find.byKey(const ValueKey('sync-obsidian'));
      await tester.ensureVisible(sync);
      await tester.tap(sync);
      await tester.pumpAndSettle();
      expect(find.textContaining('模拟同步失败'), findsOneWidget);
      expect(
        tester.widget<TextField>(folder).controller!.text,
        'synthetic/Daymark',
      );
      fail = false;
      await tester.ensureVisible(sync);
      await tester.tap(sync);
      await tester.pumpAndSettle();
      expect(find.text('已同步 5 个事项'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('save-settings')));
      await tester.pumpAndSettle();
      expect(saved!.obsidianDirectory, 'synthetic/Daymark');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
