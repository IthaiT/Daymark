import 'dart:io';

import 'package:daymark/application/journal_controller.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/item.dart';
import 'package:daymark/domain/model.dart';
import 'package:daymark/ui/inline_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late Store store;
  late EditSession session;
  final day = DateTime.utc(2026, 11, 5);

  setUp(() async {
    directory = await (await Directory(
      '.test-artifacts',
    ).create()).createTemp('inline-');
    store = await Store.open(directory, writer: (file, bytes) async {});
    await store.saveItem(const Item(id: 'job', name: '跳槽'));
    await store.saveItem(
      const Item(id: 'resume', name: '改简历', parentId: 'job'),
    );
    session = EditSession(
      Event('draft', '', null, day, day.add(const Duration(hours: 1))),
      EventColumn.title,
    );
  });

  tearDown(() async {
    session.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 420,
              child: InlineEditor(
                session: session,
                store: store,
                day: day,
                onCommit: () async => true,
                onCompleteChoice: () {},
                onCancel: () {},
                onNext: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ending Chinese composition brings the suggestions back', (
    tester,
  ) async {
    await open(tester);
    const composing = TextEditingValue(
      text: '简历',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    );
    tester.testTextInput.updateEditingValue(composing);
    await tester.pumpAndSettle();
    expect(session.pickerOpen, isFalse);

    tester.testTextInput.updateEditingValue(
      composing.copyWith(composing: TextRange.empty),
    );
    await tester.pumpAndSettle();

    expect(session.text.value.composing, TextRange.empty);
    expect(session.pickerOpen, isTrue);
    expect(
      find.byKey(const ValueKey('title-choice-item-resume')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('arrow keys stay with the IME while it is composing', (
    tester,
  ) async {
    await open(tester);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '简',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 1),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(session.titleIndex, 0);
    expect(session.pickerOpen, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
