import 'dart:io';

import 'package:daymark/application/journal_controller.dart';
import 'package:daymark/data/archive_store.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/event_clipboard.dart';
import 'package:daymark/domain/model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime.utc(2026, 10, 24);
  late DateTime now;
  late Directory directory;
  late Store store;
  late ArchiveStore archive;
  late JournalController journal;
  Event item(String id, int start, int end) => Event(
    id,
    id,
    'work',
    day.add(Duration(hours: start)),
    day.add(Duration(hours: end)),
  );
  Future<void> open() async {
    archive = await ArchiveStore.open(directory);
    journal = JournalController(
      store,
      archive: archive,
      day: day,
      clock: () => now,
    );
    await journal.initialize();
  }

  setUp(() async {
    now = day.add(const Duration(days: 1, hours: 9));
    directory = await (await Directory(
      '.test-artifacts',
    ).create()).createTemp('archive-controller-');
    store = await Store.open(directory);
    await store.replaceEvents({'a': item('a', 0, 10), 'b': item('b', 12, 26)});
    await open();
  });
  tearDown(() async {
    journal.dispose();
    await directory.delete(recursive: true);
  });
  test(
    'startup archives complete dates and protects full overnight records',
    () {
      expect(archive.days, {day});
      expect(archive.events['b'], store.events['b']);
      expect(journal.canEditEvent(store.events['b']!), isFalse);
      expect(journal.canEditDay(now), isTrue);
      expect(journal.allowHistoryEditing, isFalse);
    },
  );
  test(
    'all requested history edits reject atomically while tags remain editable',
    () async {
      final original = store.events;
      final actions = <Future<void> Function()>[
        () async {
          await journal.editCell('a', EventColumn.title, '改名');
        },
        () async {
          await journal.editCell(
            'a',
            EventColumn.start,
            day.add(const Duration(hours: 1)),
          );
        },
        () async {
          await journal.editCell(
            'a',
            EventColumn.end,
            day.add(const Duration(hours: 9)),
          );
        },
        () => journal.updateEvent(store.events['a']!.copyWith(notes: '修改备注')),
        () async {
          journal.select('a');
          await journal.deleteSelected();
        },
        () async {
          await journal.addDraft();
        },
        () async {
          await journal.pasteEvents(EventClipboard(day, [item('copy', 1, 2)]));
        },
      ];
      for (final action in actions) {
        await expectLater(action(), throwsFormatException);
        expect(store.events, original);
      }
      await journal.editCell('a', EventColumn.tag, 'life');
      expect(store.events['a']!.tagId, 'life');
      expect(store.events['a']!.title, 'a');
      await journal.setEventTag(['a', 'b'], 'rest');
      expect(store.events['b']!.tagId, 'rest');
    },
  );
  test(
    'unarchived edits work and moves into protected dates are rejected',
    () async {
      await journal.setDay(now);
      final id = await journal.addDraft(
        start: day.add(const Duration(hours: 27)),
      );
      await journal.editCell(id, EventColumn.title, '今天');
      final saved = store.events[id]!;
      await expectLater(
        journal.updateEvent(
          saved.copyWith(start: day.add(const Duration(hours: 23))),
        ),
        throwsFormatException,
      );
      expect(store.events[id], saved);
      await journal.editCell(id, EventColumn.title, '今天的记录');
      expect(store.events[id]!.title, '今天的记录');
    },
  );
  test(
    'session override resets on reopen and explicit corrections update one backup',
    () async {
      journal.setAllowHistoryEditing(true);
      await journal.editCell('a', EventColumn.title, '手动更正');
      journal.setAllowHistoryEditing(false);
      await journal.archiveForClose();
      expect((await ArchiveStore.open(directory)).events['a']!.title, '手动更正');
      journal.dispose();
      store = await Store.open(directory);
      await open();
      expect(journal.allowHistoryEditing, isFalse);
      await expectLater(
        journal.editCell('a', EventColumn.title, '意外修改'),
        throwsFormatException,
      );
    },
  );
  test('undo and redo obey the current history permission', () async {
    journal.setAllowHistoryEditing(true);
    await journal.editCell('a', EventColumn.title, '更正');
    journal.setAllowHistoryEditing(false);
    await expectLater(journal.undo(), throwsFormatException);
    expect(journal.history.canUndo, isTrue);
    expect(store.events['a']!.title, '更正');
    journal.setAllowHistoryEditing(true);
    await journal.undo();
    journal.setAllowHistoryEditing(false);
    await expectLater(journal.redo(), throwsFormatException);
    expect(journal.history.canRedo, isTrue);
  });
  test(
    'archived gap tagging keeps its original title, notes and interval',
    () async {
      final gap = journal.rows.singleWhere((event) => event.isUndefined);
      await expectLater(
        journal.editCell(gap.id, EventColumn.title, '改名'),
        throwsFormatException,
      );
      final id = await journal.editCell(gap.id, EventColumn.tag, 'life');
      final promoted = store.events[id]!;
      expect(promoted.title, gap.title);
      expect(promoted.start, gap.start);
      expect(promoted.end, gap.end);
      expect(promoted.notes, gap.notes);
      await journal.undo();
      expect(store.events[gap.id], gap);
      await journal.redo();
      expect(store.events[id], promoted);
      await journal.archiveForClose();
      expect((await ArchiveStore.open(directory)).events[id], promoted);
    },
  );
  test(
    'close archives dates completed during an open session after queued saves',
    () async {
      journal.setAllowHistoryEditing(true);
      final future = journal.updateEvent(item('b', 12, 50));
      now = day.add(const Duration(days: 2, hours: 9));
      await journal.archiveForClose();
      await future;
      expect(archive.days, {day, day.add(const Duration(days: 1))});
      expect(archive.events['b']!.end, day.add(const Duration(hours: 50)));
    },
  );
}
