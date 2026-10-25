import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:daymark/application/journal_controller.dart';
import 'package:daymark/application/ledger_controller.dart';
import 'package:daymark/application/settings_controller.dart';
import 'package:daymark/data/archive_store.dart';
import 'package:daymark/data/ledger_store.dart';
import 'package:daymark/data/settings_store.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/model.dart';
import 'package:daymark/main.dart';
import 'package:daymark/ui/timeline.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

import 'support/screenshot_fonts.dart';

void main() {
  final day = DateTime.utc(2026, 10, 24);
  final boundary = GlobalKey();
  late DateTime now;
  late Directory directory;
  late Store store;
  late ArchiveStore archive;
  late LedgerStore ledgerStore;
  late SettingsStore settingsStore;
  late JournalController journal;
  late LedgerController ledger;
  late SettingsController settings;
  bool failArchive = false;
  String? savedSettings;
  final windowCalls = <String>[];
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    now = day.add(const Duration(days: 1, hours: 9));
    failArchive = false;
    savedSettings = null;
    windowCalls.clear();
    directory = await (await Directory(
      '.test-artifacts',
    ).create()).createTemp('archive-widgets-');
    store = await Store.open(directory, writer: (_, _) async {});
    await store.replaceEvents({
      'a': Event(
        'a',
        '合成工作记录',
        'work',
        day,
        day.add(const Duration(hours: 10)),
      ),
      'b': Event(
        'b',
        '合成跨天记录',
        'life',
        day.add(const Duration(hours: 12)),
        day.add(const Duration(hours: 26)),
      ),
    });
    archive = await ArchiveStore.open(
      directory,
      writer: (_, _) async {
        if (failArchive) throw const FileSystemException('模拟归档失败');
      },
    );
    ledgerStore = await LedgerStore.open(directory, writer: (_, _) async {});
    settingsStore = await SettingsStore.open(
      directory,
      writer: (_, bytes) async {
        savedSettings = utf8.decode(bytes);
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), (
          call,
        ) async {
          windowCalls.add(call.method);
          return null;
        });
  });
  tearDown(() async {
    journal.dispose();
    ledger.dispose();
    settings.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
    await directory.delete(recursive: true);
  });
  Future<void> open(WidgetTester tester) async {
    journal = JournalController(
      store,
      archive: archive,
      day: day,
      clock: () => now,
    );
    await journal.initialize();
    ledger = LedgerController(ledgerStore);
    settings = SettingsController(settingsStore);
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: DaymarkApp(journal: journal, ledger: ledger, settings: settings),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('settings')));
    await tester.pumpAndSettle();
  }

  Future<void> override(WidgetTester tester) async {
    await openSettings(tester);
    await tester.tap(find.byKey(const ValueKey('setting-history-editing')));
    await tester.tap(find.byKey(const ValueKey('save-settings')));
    await tester.pumpAndSettle();
  }

  Future<void> drag(WidgetTester tester, double hour) async {
    final rect = tester.getRect(find.byType(Timeline));
    final width = rect.width - 50;
    final gesture = await tester.startGesture(
      Offset(rect.left + 24 + width * hour / 24, rect.top + 120),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(Offset(width / 24, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    (tester.state(find.byType(DaymarkApp)) as WindowListener).onWindowClose();
    await tester.pumpAndSettle();
  }

  testWidgets(
    'protected timeline, table, context actions and Delete do not edit history',
    (tester) async {
      await open(tester);
      final before = store.events;
      expect(find.text('已归档 · 仅可修改标签'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('add-event')))
            .onPressed,
        isNull,
      );
      final title = find.byKey(const ValueKey('cell-a-title'));
      await tester.tap(title);
      await tester.tap(title);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('input-a-title')), findsNothing);
      await drag(tester, 5);
      await drag(tester, 10);
      expect(store.events, before);
      await tester.tap(title, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PopupMenuItem<String>>(
              find.widgetWithText(PopupMenuItem<String>, '删除'),
            )
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<PopupMenuItem<String>>(
              find.widgetWithText(PopupMenuItem<String>, '编辑详情'),
            )
            .enabled,
        isFalse,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(store.events, before);
      final tag = find.byKey(const ValueKey('cell-a-tag'));
      await tester.tap(tag);
      await tester.tap(tag);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('input-a-tag')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'settings override enables edits, stays out of JSON and can be disabled',
    (tester) async {
      await open(tester);
      await override(tester);
      expect(journal.allowHistoryEditing, isTrue);
      expect(find.text('历史编辑已开启'), findsOneWidget);
      expect(savedSettings, isNull);
      final before = store.events['a']!;
      await drag(tester, 5);
      expect(
        store.events['a']!.start,
        before.start.add(const Duration(hours: 1)),
      );
      await override(tester);
      expect(journal.allowHistoryEditing, isFalse);
      final locked = store.events['a'];
      await drag(tester, 6);
      expect(store.events['a'], locked);
    },
  );
  testWidgets(
    'canceling the settings dialog leaves history protection enabled',
    (tester) async {
      await open(tester);
      await openSettings(tester);
      await tester.tap(find.byKey(const ValueKey('setting-history-editing')));
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(journal.allowHistoryEditing, isFalse);
    },
  );
  testWidgets(
    'native close commits the active editor and archives before closing the host window',
    (tester) async {
      await open(tester);
      await override(tester);
      final title = find.byKey(const ValueKey('cell-a-title'));
      await tester.tap(title);
      await tester.tap(title);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('input-a-title')),
        '关闭前更正',
      );
      await close(tester);
      expect(store.events['a']!.title, '关闭前更正');
      expect(archive.events['a']!.title, '关闭前更正');
      expect(windowCalls, ['setPreventClose', 'close']);
    },
  );
  testWidgets('failed close archive keeps the window open and can retry', (
    tester,
  ) async {
    await open(tester);
    journal.setAllowHistoryEditing(true);
    await journal.updateEvent(
      store.events['b']!.copyWith(end: day.add(const Duration(hours: 50))),
    );
    now = day.add(const Duration(days: 2, hours: 9));
    failArchive = true;
    await close(tester);
    expect(windowCalls, isNot(contains('close')));
    expect(find.textContaining('模拟归档失败'), findsOneWidget);
    expect(archive.days, {day});
    failArchive = false;
    await close(tester);
    expect(windowCalls, contains('close'));
    expect(archive.days, {day, day.add(const Duration(days: 1))});
  });
  testWidgets(
    'renders protected journal and session settings using synthetic data',
    (tester) async {
      await loadScreenshotFonts(tester);
      await open(tester);
      Future<void> capture(String name) async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = (await tester.runAsync(
          () => render.toImage(pixelRatio: 1),
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

      await capture('archive-protected-journal');
      await openSettings(tester);
      await capture('archive-session-settings');
      expect(tester.takeException(), isNull);
    },
  );
}
