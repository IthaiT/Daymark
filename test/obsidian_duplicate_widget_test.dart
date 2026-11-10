import 'dart:io';
import 'dart:ui' as ui;

import 'package:daymark/application/journal_controller.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/obsidian.dart';
import 'package:daymark/domain/settings.dart';
import 'package:daymark/main.dart';
import 'package:daymark/ui/obsidian_sync_error.dart';
import 'package:daymark/ui/project_screen.dart';
import 'package:daymark/ui/settings_dialog.dart';
import 'package:daymark/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/obsidian_ids.dart';
import 'support/screenshot_fonts.dart';

class _DuplicateJournal extends JournalController {
  _DuplicateJournal(super.store, this.error)
    : super(
        settings: const AppSettings(obsidianDirectory: 'synthetic/Daymark'),
      );

  final ObsidianDuplicateIdException error;

  @override
  Future<int> syncObsidian(String path) async => throw error;
}

void main() {
  late Directory directory;
  late Store store;
  late ObsidianDuplicateIdException duplicate;

  setUp(() async {
    directory = await (await Directory(
      '.test-artifacts',
    ).create()).createTemp('obsidian-duplicate-ui-');
    store = await Store.open(directory, writer: (_, _) async {});
    try {
      var counter = 0;
      parseObsidian(
        {
          '工作计划.md': '- [ ] 准备面试 ${obsidianId(99)}\n',
          '面试副本.md': '副本正文\n- [ ] 准备面试副本 ${obsidianId(99)}\n',
        },
        directory: 'synthetic/Daymark',
        newId: () => obsidianId(counter++),
      );
      fail('Expected a duplicate ID error.');
    } on ObsidianDuplicateIdException catch (error) {
      duplicate = error;
    }
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  void size(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  void expectLocations() {
    expect(
      find.byKey(const ValueKey('obsidian-duplicate-dialog')),
      findsOneWidget,
    );
    final text = find.byWidgetPredicate(
      (widget) => widget is SelectableText && widget.data == duplicate.message,
    );
    expect(text, findsOneWidget);
    expect(duplicate.message, contains('事项「准备面试」— 工作计划.md 第 1 行'));
    expect(duplicate.message, contains('事项「准备面试副本」— 面试副本.md 第 2 行'));
  }

  testWidgets('project sync shows persistent copyable source locations', (
    tester,
  ) async {
    size(tester);
    if (const bool.fromEnvironment('DAYMARK_CAPTURE_UI')) {
      await loadScreenshotFonts(tester);
    }
    final journal = _DuplicateJournal(store, duplicate);
    addTearDown(journal.dispose);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          theme: daymarkTheme(),
          home: Scaffold(body: ProjectScreen(journal: journal)),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('project-sync')));
    await tester.pumpAndSettle();
    expectLocations();
    expect(find.byKey(const ValueKey('project-error-toast')), findsNothing);
    await tester.pump(const Duration(seconds: 10));
    expectLocations();
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.text('复制详情'));
    await tester.pumpAndSettle();
    expect(copied, duplicate.message);
    if (const bool.fromEnvironment('DAYMARK_CAPTURE_UI')) {
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '.test-artifacts/obsidian-duplicate-dialog.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('obsidian-duplicate-dialog')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('settings sync preserves directory input and allows retry', (
    tester,
  ) async {
    size(tester);
    var failSync = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: daymarkTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showSettingsDialog(
                context,
                settings: const AppSettings(
                  obsidianDirectory: 'synthetic/Daymark',
                ),
                onSave: (_) async {},
                onSyncObsidian: (_) async {
                  if (failSync) throw duplicate;
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
    final sync = find.byKey(const ValueKey('sync-obsidian'));
    await tester.ensureVisible(sync);
    await tester.tap(sync);
    await tester.pumpAndSettle();
    expectLocations();
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    final folder = tester.widget<TextField>(
      find.byKey(const ValueKey('setting-obsidian-directory')),
    );
    expect(folder.controller!.text, 'synthetic/Daymark');
    failSync = false;
    await tester.ensureVisible(sync);
    await tester.tap(sync);
    await tester.pumpAndSettle();
    expect(find.text('已同步 5 个事项'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('startup sync shows the same duplicate details dialog', (
    tester,
  ) async {
    size(tester);
    final journal = _DuplicateJournal(store, duplicate);
    addTearDown(journal.dispose);
    await tester.pumpWidget(DaymarkApp(journal: journal));
    await tester.pumpAndSettle();
    expectLocations();
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('many conflict groups scroll without hiding dialog actions', (
    tester,
  ) async {
    size(tester);
    final longError = ObsidianDuplicateIdException(
      List.generate(
        30,
        (i) => '重复组 ${i + 1}：\n• 事项「第 $i 条」— 计划.md 第 $i 行\n',
      ).join(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: daymarkTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showObsidianDuplicateError(context, longError),
              child: const Text('查看冲突'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('查看冲突'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    expect(find.text('复制详情').hitTestable(), findsOneWidget);
    expect(find.text('关闭').hitTestable(), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
