import 'dart:io';

import 'package:daymark/application/journal_controller.dart';
import 'package:daymark/data/atomic_file.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/model.dart';
import 'package:flutter_test/flutter_test.dart';

final throwsFileSystemException = throwsA(isA<FileSystemException>());

void main() {
  late Directory directory;
  late Store store;
  late JournalController controller;
  var failWrites = false;
  var writes = 0;
  final day = DateTime.utc(2026, 10, 7);
  setUp(() async {
    directory = await (await Directory(
      '.test-artifacts',
    ).create()).createTemp('controller-');
    failWrites = false;
    writes = 0;
    store = await Store.open(
      directory,
      writer: (file, bytes) async {
        if (failWrites) throw const FileSystemException('模拟失败');
        writes++;
        await AtomicFile.write(file, bytes);
      },
    );
    controller = JournalController(
      store,
      day: day,
      clock: () => DateTime.utc(2026, 10, 7, 12),
    );
    await controller.initialize();
  });
  tearDown(() async {
    controller.dispose();
    await directory.delete(recursive: true);
  });
  Event item(String id, int start, int end) => Event(
    id,
    id,
    'linux',
    day.add(Duration(hours: start)),
    day.add(Duration(hours: end)),
  );

  test(
    'multiple drafts independently move and become saved only when named',
    () async {
      final first = await controller.addDraft();
      final second = await controller.addDraft(
        start: day.add(const Duration(hours: 13)),
      );
      await controller.updateEvent(
        moveEventOnDay(controller.event(first)!, day, 60),
      );
      expect(controller.drafts.length, 2);
      expect(store.events.values.where((event) => !event.isUndefined), isEmpty);
      await controller.editCell(first, EventColumn.title, '独立命名');
      expect(controller.drafts.keys, [second]);
      expect(store.events[first]!.start.hour, 12);
      await controller.undo();
      expect(controller.drafts[first]!.title, '');
      await controller.redo();
      expect(store.events[first]!.title, '独立命名');
    },
  );

  test(
    'draft create and discard undo in small steps and new edits clear redo',
    () async {
      final first = await controller.addDraft();
      final second = await controller.addDraft();
      await controller.undo();
      expect(controller.drafts.keys, [first]);
      await controller.redo();
      await controller.discardDraft(second);
      await controller.undo();
      expect(controller.drafts.keys.toSet(), {first, second});
      await controller.editCell(first, EventColumn.title, '新事件');
      expect(controller.history.canRedo, isFalse);
    },
  );

  test(
    'gap rename survives boundary changes and promotion only happens on tag assignment',
    () async {
      await store.replaceEvents({
        'a': item('a', 9, 10),
        'b': item('b', 12, 13),
      });
      await controller.initialize();
      final gap = controller.rows.singleWhere(
        (event) => event.isUndefined && event.start.hour == 10,
      );
      await controller.editCell(gap.id, EventColumn.title, '煮饭');
      await controller.updateEvent(item('a', 9, 11));
      expect(controller.event(gap.id)!.title, '煮饭');
      expect(controller.event(gap.id)!.start.hour, 11);
      expect((await Store.open(directory)).events[gap.id]!.title, '煮饭');
      final promoted = await controller.editCell(
        gap.id,
        EventColumn.tag,
        'work',
      );
      expect(promoted.startsWith(undefinedIdPrefix), isFalse);
      expect(store.events[promoted]!.tagId, 'work');
      expect(controller.event(gap.id), isNull);
      await controller.undo();
      expect(controller.event(gap.id)!.title, '煮饭');
      expect(controller.event(promoted), isNull);
    },
  );

  test(
    'delete mixed selection keeps unrelated drafts and derived rows, undo restores all',
    () async {
      await store.saveEvent(item('saved', 9, 10));
      final first = await controller.addDraft(
        start: day.add(const Duration(hours: 11)),
      );
      final second = await controller.addDraft(
        start: day.add(const Duration(hours: 13)),
      );
      controller.select('saved');
      controller.select(first, toggle: true);
      await controller.deleteSelected();
      expect(controller.drafts.keys, [second]);
      expect(store.events.values.where((event) => !event.isUndefined), isEmpty);
      await controller.undo();
      expect(store.events.containsKey('saved'), isTrue);
      expect(controller.drafts.keys.toSet(), {first, second});
    },
  );

  test(
    'failed transaction retains events, drafts, gap titles, selection and history',
    () async {
      final draft = await controller.addDraft();
      final oldBytes = await store.eventsFile.readAsBytes();
      final oldRows = controller.rows;
      failWrites = true;
      await expectLater(
        controller.editCell(draft, EventColumn.title, '未保存'),
        throwsFileSystemException,
      );
      expect(controller.drafts[draft]!.title, '');
      expect(controller.selected, {draft});
      expect(controller.rows, oldRows);
      expect(await store.eventsFile.readAsBytes(), oldBytes);
      failWrites = false;
      await controller.undo();
      expect(controller.drafts, isEmpty);
    },
  );

  test('event mutation and gap sync are a single atomic write', () async {
    await store.replaceEvents({'a': item('a', 9, 10), 'b': item('b', 12, 13)});
    await controller.initialize();
    final before = writes;
    await controller.updateEvent(item('a', 9, 11));
    expect(writes - before, 1);
    final restored = await Store.open(directory);
    expect(restored.events['a']!.end!.hour, 11);
    expect(
      restored.events.values
          .singleWhere((event) => event.isUndefined && event.start.hour == 11)
          .end!
          .hour,
      12,
    );
  });

  test(
    'serialized simultaneous edits retain both results and undo ordering',
    () async {
      await store.replaceEvents({
        'a': item('a', 9, 10),
        'b': item('b', 12, 13),
      });
      await controller.initialize();
      await Future.wait([
        controller.editCell('a', EventColumn.title, 'first'),
        controller.editCell('b', EventColumn.title, 'second'),
      ]);
      expect(store.events['a']!.title, 'first');
      expect(store.events['b']!.title, 'second');
      await controller.undo();
      expect(store.events['a']!.title, 'first');
      expect(store.events['b']!.title, 'b');
    },
  );

  test(
    'date navigation discards drafts, synchronizes their gaps and leaves no blank-day rows',
    () async {
      await controller.addDraft();
      await controller.shiftDay(1);
      expect(controller.drafts, isEmpty);
      expect(controller.rows, isEmpty);
      expect(store.events, isEmpty);
    },
  );

  test('failed undo keeps history available for retry', () async {
    final id = await controller.addDraft();
    await controller.editCell(id, EventColumn.title, '记录');
    failWrites = true;
    await expectLater(controller.undo(), throwsFileSystemException);
    expect(controller.history.canUndo, isTrue);
    expect(store.events[id]!.title, '记录');
    failWrites = false;
    expect(await controller.undo(), isTrue);
    expect(controller.drafts[id]!.title, '');
  });

  test(
    'legacy unfinished event title remains editable without inventing end',
    () async {
      await store.replaceEvents({
        'old': Event('old', '旧事件', 'work', day, null),
      });
      await controller.initialize();
      await controller.editCell('old', EventColumn.title, '新名称');
      expect(store.events['old']!.end, isNull);
      await controller.editCell(
        'old',
        EventColumn.end,
        day.add(const Duration(hours: 1)),
      );
      expect(
        store.events['old']!.intervalOn(day)!.duration,
        const Duration(hours: 1),
      );
    },
  );
}
