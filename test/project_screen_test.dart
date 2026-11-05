import 'dart:io';

import 'package:daymark/application/journal_controller.dart';
import 'package:daymark/data/atomic_file.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/item.dart';
import 'package:daymark/domain/model.dart';
import 'package:daymark/ui/project_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late JournalController journal;
  var failWrites = false;
  final day = DateTime.utc(2026, 11, 4);
  setUp(() async {
    failWrites = false;
    directory = await (await Directory(
      '.test-artifacts',
    ).create()).createTemp('projects-');
    var initializing = true;
    final store = await Store.open(
      directory,
      writer: (file, bytes) async {
        if (failWrites) throw const FileSystemException('items write denied');
        // Real file IO never completes inside a widget test's fake async zone.
        if (initializing) await AtomicFile.write(file, bytes);
      },
    );
    initializing = false;
    journal = JournalController(store, day: day);
  });
  tearDown(() async {
    journal.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProjectScreen(journal: journal)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a failed save keeps the dialog and everything typed in it', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('project-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('project-name')),
      '已经填写的项目',
    );
    failWrites = true;
    await tester.tap(find.byKey(const ValueKey('project-save')));
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();

    expect(journal.store.items, isEmpty);
    expect(find.byKey(const ValueKey('project-name')), findsOneWidget);
    expect(find.text('已经填写的项目'), findsOneWidget);

    failWrites = false;
    final retry = tester.widget<FilledButton>(
      find.byKey(const ValueKey('project-save')),
    );
    expect(retry.onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('project-save')));
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(journal.store.items.length, 1);
  });

  testWidgets('an empty name keeps the dialog open with an explanation', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('project-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(journal.store.items, isEmpty);
    expect(find.text('事项 ID 和名称不能为空。'), findsOneWidget);
    expect(find.byKey(const ValueKey('project-name')), findsOneWidget);
  });

  testWidgets('lists planned items and shows the selected project', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await journal.saveItem(
        const Item(id: 'job', name: '跳槽', objective: '三月前拿到 offer'),
      );
      await journal.saveItem(
        const Item(id: 'resume', name: '改简历', parentId: 'job'),
      );
    });
    await pump(tester);

    expect(find.text('改简历'), findsOneWidget);
    expect(find.byKey(const ValueKey('project-child-resume')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('project-job')));
    await tester.pumpAndSettle();

    expect(find.text('三月前拿到 offer'), findsOneWidget);
    expect(find.text('还没有记录时间'), findsOneWidget);
    expect(find.byKey(const ValueKey('project-child-resume')), findsOneWidget);
  });

  testWidgets('rolls recorded time from a child into its project', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await journal.saveItem(const Item(id: 'job', name: '跳槽'));
      await journal.saveItem(
        const Item(id: 'resume', name: '改简历', parentId: 'job'),
      );
      await journal.store.saveEvent(
        Event(
          'a',
          '改简历',
          null,
          day.add(const Duration(hours: 9)),
          day.add(const Duration(hours: 10)),
          '',
          'resume',
        ),
      );
    });
    await pump(tester);

    expect(find.text('1 小时 00 分'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('project-job')));
    await tester.pumpAndSettle();

    expect(find.text('累计 1 小时 00 分 · 1 条记录'), findsOneWidget);
  });

  testWidgets('a deleted project disappears from the tree', (tester) async {
    await tester.runAsync(
      () => journal.saveItem(const Item(id: 'job', name: '跳槽')),
    );
    await pump(tester);
    expect(find.byKey(const ValueKey('project-job')), findsOneWidget);

    await tester.runAsync(() => journal.deleteItem('job'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('project-job')), findsNothing);
    expect(find.text('还没有项目'), findsOneWidget);
  });
}
