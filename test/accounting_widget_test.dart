import 'dart:io';
import 'package:daymark/application/journal_controller.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/model.dart';
import 'package:daymark/domain/settings.dart';
import 'package:daymark/ui/event_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final mode in EventTableMode.values) {
    testWidgets(
      '${mode.name} uses saved-event shares even with drafts and filtering',
      (tester) async {
        final directory = (await tester.runAsync(
          () => Directory('.test-artifacts').createTemp('accounting-'),
        ))!;
        final store = (await tester.runAsync(
          () => Store.open(directory, writer: (_, _) async {}),
        ))!;
        final day = DateTime.utc(2026, 11, 7);
        await store.replaceEvents({
          'discussion': Event(
            'discussion',
            '讨论',
            'work',
            day.add(const Duration(hours: 17)),
            day.add(const Duration(hours: 21, minutes: 30)),
          ),
          'dinner': Event(
            'dinner',
            '晚餐',
            'life',
            day.add(const Duration(hours: 17)),
            day.add(const Duration(hours: 17, minutes: 30)),
          ),
        });
        final journal = JournalController(
          store,
          day: day,
          settings: const AppSettings(splitOverlap: true),
        );
        addTearDown(() async {
          journal.dispose();
          await tester.runAsync(() => directory.delete(recursive: true));
        });
        await journal.initialize();
        final draft = await journal.addDraft(
          start: day.add(const Duration(hours: 17)),
        );
        await journal.editCell(draft, EventColumn.title, '尚未分类');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EventTable(
                journal: journal,
                mode: mode,
                events: [store.events['discussion']!],
                onCell: (_, _) {},
                onBlank: () {},
                onAdd: () {},
                onContext: (_, _) {},
                beforeScroll: () async => true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('4 小时 15 分'), findsOneWidget);
        expect(find.text('4 小时 30 分'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
