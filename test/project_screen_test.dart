import 'dart:io';

import 'package:daymark/application/journal_controller.dart';
import 'package:daymark/data/atomic_file.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/item.dart';
import 'package:daymark/domain/model.dart';
import 'package:daymark/ui/project_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Finder add() => find.byKey(const ValueKey('project-add'));
  Finder addChild() => find.byKey(const ValueKey('project-add-child'));
  Finder nameField() => find.byKey(const ValueKey('project-name'));
  Finder descriptionField() =>
      find.byKey(const ValueKey('project-description'));
  Finder resultField() => find.byKey(const ValueKey('project-result'));

  /// Adds a tag through the search bar, which is the only way tags are picked.
  /// Lets the debounced write and the controller's queue finish.
  Future<void> settleWrite(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 700));
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
  }

  /// Adds a tag through the search bar, which is the only way tags are picked.
  Future<void> addTag(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(const ValueKey('project-tag-search')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('project-tag-search')),
      name,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('project-tag-work')));
    await settleWrite(tester);
  }

  /// Typing a name and pressing Enter creates the node, no dialog involved.
  Future<void> addRoot(WidgetTester tester, String name) async {
    await tester.enterText(add(), '$name\n');
    await settleWrite(tester);
  }

  Future<void> addChildNamed(WidgetTester tester, String name) async {
    await tester.enterText(addChild(), '$name\n');
    await settleWrite(tester);
  }

  testWidgets('typing a name creates a project without a dialog', (
    tester,
  ) async {
    await pump(tester);
    expect(find.textContaining('还没有项目'), findsOneWidget);

    await addRoot(tester, '跳槽');
    expect(journal.store.items.length, 1);
    final item = journal.store.items.values.single;
    expect(item.name, '跳槽');
    expect(find.text('跳槽'), findsOneWidget);

    // The new node opens straight away, ready for its description.
    await tester.tap(find.byKey(ValueKey('project-${item.id}')));
    await tester.pumpAndSettle();
    expect(nameField(), findsOneWidget);
  });

  testWidgets('children paste in as several nodes at any depth', (
    tester,
  ) async {
    await pump(tester);
    await addRoot(tester, '跳槽');
    final root = journal.store.items.values.single;
    await tester.tap(find.byKey(ValueKey('project-${root.id}')));
    await tester.pumpAndSettle();

    await tester.enterText(addChild(), '改简历\n调研 A 公司\n复习算法');
    await settleWrite(tester);
    expect(journal.store.items.length, 4);

    final child = journal.store.items.values.firstWhere(
      (item) => item.name == '改简历',
    );
    // Drill down and add a grandchild, then one more level: no depth cap.
    await tester.tap(find.byKey(ValueKey('project-child-${child.id}')));
    await tester.pumpAndSettle();
    await addChildNamed(tester, '改前两段');
    final grandchild = journal.store.items.values.firstWhere(
      (item) => item.name == '改前两段',
    );
    await tester.tap(find.byKey(ValueKey('project-child-${grandchild.id}')));
    await tester.pumpAndSettle();
    await addChildNamed(tester, '量化成果');

    final deepest = journal.store.items.values.firstWhere(
      (item) => item.name == '量化成果',
    );
    expect(itemAncestors(journal.store.items, deepest.id).length, 3);
  });

  testWidgets('description and result save themselves', (tester) async {
    await pump(tester);
    await addRoot(tester, '跳槽');
    final item = journal.store.items.values.single;
    await tester.tap(find.byKey(ValueKey('project-${item.id}')));
    await tester.pumpAndSettle();

    await tester.enterText(descriptionField(), '三月前拿到 offer');
    await tester.enterText(resultField(), '拿到了两个');
    await settleWrite(tester);

    expect(journal.store.items[item.id]!.objective, '三月前拿到 offer');
    expect(journal.store.items[item.id]!.outcome, '拿到了两个');
  });

  testWidgets('a failed write keeps what is typed on screen', (tester) async {
    await pump(tester);
    await addRoot(tester, '跳槽');
    final item = journal.store.items.values.single;
    await tester.tap(find.byKey(ValueKey('project-${item.id}')));
    await tester.pumpAndSettle();

    failWrites = true;
    await tester.enterText(descriptionField(), '还没写进去的描述');
    await settleWrite(tester);

    expect(find.byKey(const ValueKey('project-error-toast')), findsOneWidget);
    expect(find.text('还没写进去的描述'), findsOneWidget);
    expect(journal.store.items[item.id]!.objective, isEmpty);

    failWrites = false;
  });

  testWidgets('tags apply to a node and are inherited by its children', (
    tester,
  ) async {
    await pump(tester);
    await addRoot(tester, '跳槽');
    final root = journal.store.items.values.single;
    await tester.tap(find.byKey(ValueKey('project-${root.id}')));
    await tester.pumpAndSettle();

    await addTag(tester, '主业');
    expect(journal.store.items[root.id]!.tagIds, contains('work'));

    await addChildNamed(tester, '改简历');
    final child = journal.store.items.values.firstWhere(
      (item) => item.name == '改简历',
    );
    await tester.tap(find.byKey(ValueKey('project-child-${child.id}')));
    await tester.pumpAndSettle();
    expect(find.text('主业（继承）'), findsOneWidget);

    // Dropping the inherited tag is an explicit choice on the child.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('project-chip-inherited-work')),
        matching: find.byType(Icon),
      ),
    );
    await settleWrite(tester);
    expect(journal.store.items[child.id]!.excludedTagIds, contains('work'));
    expect(find.text('主业（继承）'), findsNothing);
  });

  testWidgets('folding a branch hides its descendants', (tester) async {
    await pump(tester);
    await addRoot(tester, '跳槽');
    final root = journal.store.items.values.single;
    await tester.tap(find.byKey(ValueKey('project-${root.id}')));
    await tester.pumpAndSettle();
    await addChildNamed(tester, '改简历');
    final child = journal.store.items.values.firstWhere(
      (item) => item.name == '改简历',
    );
    expect(find.byKey(ValueKey('project-${child.id}')), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('project-toggle-${root.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('project-${child.id}')), findsNothing);

    await tester.tap(find.byKey(ValueKey('project-toggle-${root.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('project-${child.id}')), findsOneWidget);
  });

  testWidgets('a parent lists its children with their rolled up time', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await journal.saveItem(const Item(id: 'job', name: '跳槽'));
      await journal.saveItem(
        const Item(id: 'resume', name: '改简历', parentId: 'job', objective: '两页'),
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
    await tester.tap(find.byKey(const ValueKey('project-job')));
    await tester.pumpAndSettle();

    expect(find.text('1 小时 00 分'), findsWidgets);
    expect(find.textContaining('两页'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('project-child-resume')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(nameField()).controller!.text, '改简历');
  });

  testWidgets('the tag bar only lists candidates when opened', (tester) async {
    await pump(tester);
    await addRoot(tester, '跳槽');
    final item = journal.store.items.values.single;
    await tester.tap(find.byKey(ValueKey('project-${item.id}')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('project-tag-work')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('project-tag-search')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('project-tag-work')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('project-tag-search')),
      '生活',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('project-tag-work')), findsNothing);
    expect(find.byKey(const ValueKey('project-tag-life')), findsOneWidget);
  });

  testWidgets('Delete removes the selected node after confirmation', (
    tester,
  ) async {
    await pump(tester);
    await addRoot(tester, '跳槽');
    final item = journal.store.items.values.single;
    await tester.tap(find.byKey(ValueKey('project-${item.id}')));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(find.text('删除「跳槽」？'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await settleWrite(tester);
    expect(journal.store.items, isEmpty);
  });

  testWidgets('right click offers rename and add child', (tester) async {
    await pump(tester);
    await addRoot(tester, '跳槽');
    final item = journal.store.items.values.single;

    await tester.tap(
      find.byKey(ValueKey('project-${item.id}')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('新建子事项'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);

    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(nameField()).focusNode!.hasPrimaryFocus,
      isTrue,
    );
  });
}
