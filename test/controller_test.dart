import 'dart:io';

import 'package:daymark/application/journal_controller.dart';
import 'package:daymark/data/atomic_file.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/event_clipboard.dart';
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
    'range selection can follow displayed group order while timeline stays chronological',
    () async {
      await store.replaceEvents({
        'a': item('a', 9, 10),
        'b': item('b', 11, 12),
        'c': item('c', 13, 14),
      });
      controller.select('c');
      controller.select('b', range: true, orderedIds: ['c', 'a', 'b']);
      expect(controller.selected, {'c', 'a', 'b'});
      controller.select('c');
      controller.select('b', range: true);
      expect(controller.selected, {'b', 'c'});
    },
  );

  test(
    'multi-event paste keeps full overnight intervals and is one undoable write',
    () async {
      final night = Event(
        'night',
        '夜间',
        'work',
        day.subtract(const Duration(minutes: 15)),
        day.add(const Duration(hours: 2, seconds: 35)),
        '备注',
      );
      final later = item('later', 4, 5);
      await store.replaceEvents({night.id: night, later.id: later});
      await controller.initialize();
      controller.select(later.id);
      controller.select(night.id, toggle: true);
      final clipboard = EventClipboard.tryDecode(
        controller.copySelected()!.encode(),
      )!;
      final originalEvents = store.events;
      await controller.shiftDay(1);
      final beforeWrites = writes;
      final ids = await controller.pasteEvents(clipboard);
      expect(writes - beforeWrites, 1);
      expect(ids.toSet().intersection({night.id, later.id}), isEmpty);
      expect(controller.selected, ids.toSet());
      for (final (index, original) in [night, later].indexed) {
        expect(
          store.events[ids[index]],
          original.copyWith(
            id: ids[index],
            start: original.start.add(const Duration(days: 1)),
            end: original.end!.add(const Duration(days: 1)),
          ),
        );
      }
      expect((await Store.open(directory)).events, store.events);
      await controller.undo();
      expect(store.events, originalEvents);
      await controller.redo();
      expect(controller.selected, isEmpty);
      expect(store.events.containsKey(ids.first), isTrue);
    },
  );

  test(
    'paste preserves blank drafts, incomplete records and normalizes missing tags',
    () async {
      final removed = await controller.saveTag('临时标签', null);
      final clipboard = EventClipboard(day, [
        item('old', 9, 10).copyWith(tagId: removed.id),
        Event(
          'draft',
          '',
          null,
          day.add(const Duration(hours: 12)),
          day.add(const Duration(hours: 13)),
        ),
        Event(
          'legacy',
          '待补全',
          'work',
          day.add(const Duration(hours: 14, seconds: 35)),
          null,
        ),
        Event(
          'undefined:gap',
          '改名空档',
          null,
          day.add(const Duration(hours: 15)),
          day.add(const Duration(hours: 16)),
        ),
      ]);
      await controller.deleteTag(removed.id);
      final ids = await controller.pasteEvents(clipboard);
      expect(store.events[ids[0]]!.tagId, isNull);
      expect(controller.drafts[ids[1]]!.title, '');
      expect(store.events.containsKey(ids[1]), isFalse);
      expect(store.events[ids[2]]!.end, isNull);
      expect(store.events[ids[2]]!.start.second, 35);
      expect(store.events[ids[3]]!.isUndefined, isFalse);
      expect(store.events[ids[3]]!.title, '改名空档');
      await controller.shiftDay(1);
      expect(controller.drafts, isEmpty);
    },
  );

  test(
    'failed paste retains data, selection, history and clipboard for retry',
    () async {
      await store.replaceEvents({
        'a': item('a', 9, 10),
        'b': item('b', 12, 13),
      });
      await controller.initialize();
      controller.select('a');
      final clipboard = controller.copySelected()!;
      final originalRows = controller.rows;
      final originalBytes = await store.eventsFile.readAsBytes();
      final beforeWrites = writes;
      failWrites = true;
      await expectLater(
        controller.pasteEvents(clipboard),
        throwsFileSystemException,
      );
      expect(controller.rows, originalRows);
      expect(controller.selected, {'a'});
      expect(controller.history.canUndo, isFalse);
      expect(await store.eventsFile.readAsBytes(), originalBytes);
      failWrites = false;
      final ids = await controller.pasteEvents(clipboard);
      expect(writes - beforeWrites, 1);
      expect(store.events[ids.single]!.title, 'a');
    },
  );

  test(
    'paste rejects date overflow and invalid batches before changing state',
    () async {
      final clipboard = EventClipboard(day, [
        item('a', 9, 10),
        item('bad', 12, 11),
      ]);
      await expectLater(
        controller.pasteEvents(clipboard),
        throwsFormatException,
      );
      expect(controller.rows, isEmpty);
      final last = DateTime.utc(9999, 12, 31);
      await controller.setDay(last);
      await expectLater(
        controller.pasteEvents(
          EventClipboard(day, [item('overnight', 23, 25)]),
        ),
        throwsFormatException,
      );
      expect(controller.rows, isEmpty);
      expect(controller.history.canUndo, isFalse);
    },
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
      expect(store.events[first]!.start.hour, 13);
      await controller.undo();
      expect(controller.drafts[first]!.title, '');
      await controller.redo();
      expect(store.events[first]!.title, '独立命名');
    },
  );

  test(
    'new drafts follow completed events and other drafts on the viewed day',
    () async {
      await store.replaceEvents({
        'a': item('a', 9, 14),
        'b': item('b', 12, 13),
      });
      final first = await controller.addDraft();
      final second = await controller.addDraft();
      expect(controller.event(first)!.start.hour, 14);
      expect(controller.event(second)!.start.hour, 15);
      expect(controller.event(second)!.end!.hour, 16);
      await controller.shiftDay(-1);
      final past = await controller.addDraft();
      expect(
        controller.event(past)!.start,
        day.subtract(const Duration(days: 1)).add(const Duration(hours: 9)),
      );
    },
  );

  test(
    'tag supplies a blank title, persists the draft and undoes atomically',
    () async {
      final id = await controller.addDraft();
      await controller.editCell(id, EventColumn.tag, 'linux');
      expect(store.events[id]!.title, store.tagName('linux'));
      expect(controller.drafts, isEmpty);
      expect((await Store.open(directory)).events[id], store.events[id]);
      await controller.undo();
      expect(controller.drafts[id]!.title, '');
      expect(controller.drafts[id]!.tagId, isNull);
      await controller.redo();
      await controller.editCell(id, EventColumn.title, '自定义名称');
      await controller.editCell(id, EventColumn.tag, 'work');
      expect(store.events[id]!.title, '自定义名称');
      await controller.editCell(id, EventColumn.tag, null);
      expect(store.events[id]!.title, '自定义名称');
    },
  );

  test('tag names a generic gap but keeps a renamed gap title', () async {
    await store.replaceEvents({'a': item('a', 9, 10), 'b': item('b', 12, 13)});
    await controller.initialize();
    final gap = controller.rows.singleWhere((event) => event.isUndefined);
    final promoted = await controller.editCell(gap.id, EventColumn.tag, 'work');
    expect(store.events[promoted]!.title, store.tagName('work'));
  });

  test(
    'failed tag default retains blank draft and selection for retry',
    () async {
      final id = await controller.addDraft();
      final before = await store.eventsFile.readAsBytes();
      failWrites = true;
      await expectLater(
        controller.editCell(id, EventColumn.tag, 'work'),
        throwsFileSystemException,
      );
      expect(controller.drafts[id]!.title, '');
      expect(controller.drafts[id]!.tagId, isNull);
      expect(controller.selected, {id});
      expect(await store.eventsFile.readAsBytes(), before);
      failWrites = false;
      await controller.editCell(id, EventColumn.tag, 'work');
      expect(store.events[id]!.title, store.tagName('work'));
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

  test(
    'startup removes an obsolete first-day head and retains real gap metadata',
    () async {
      final sleep = Event(
        'sleep',
        '睡觉',
        'rest',
        day.add(const Duration(hours: 23, minutes: 49)),
        day.add(const Duration(days: 1, hours: 7, minutes: 40)),
      );
      final breakfast = Event(
        'breakfast',
        '早餐',
        'life',
        day.add(const Duration(days: 1, hours: 9)),
        day.add(const Duration(days: 1, hours: 10)),
      );
      final oldHead = Event(
        undefinedHeadId(day),
        '未定义',
        null,
        day,
        sleep.start,
      );
      final realGap = undefinedEvents([sleep, breakfast])
          .singleWhere((gap) => gap.start == sleep.end)
          .copyWith(title: '准备早餐', notes: '保留备注');
      await store.replaceEvents({
        sleep.id: sleep,
        breakfast.id: breakfast,
        oldHead.id: oldHead,
        realGap.id: realGap,
      });
      final beforeWrites = writes;
      await controller.initialize();
      expect(controller.rows, [sleep]);
      expect(store.events, {
        sleep.id: sleep,
        breakfast.id: breakfast,
        realGap.id: realGap,
      });
      expect(writes - beforeWrites, 1);
      expect((await Store.open(directory)).events, store.events);
      await controller.initialize();
      expect(writes - beforeWrites, 1);
      await controller.shiftDay(1);
      expect(controller.rows, [sleep, realGap, breakfast]);
    },
  );

  test(
    'failed obsolete-head cleanup preserves the original data for retry',
    () async {
      final first = item('first', 9, 10);
      final oldHead = Event(
        undefinedHeadId(day),
        '未定义',
        null,
        day,
        first.start,
      );
      final original = {first.id: first, oldHead.id: oldHead};
      await store.replaceEvents(original);
      final oldBytes = await store.eventsFile.readAsBytes();
      failWrites = true;
      await expectLater(controller.initialize(), throwsFileSystemException);
      expect(store.events, original);
      expect(await store.eventsFile.readAsBytes(), oldBytes);
      failWrites = false;
      await controller.initialize();
      expect(store.events, {first.id: first});
    },
  );

  test(
    'legacy renamed head becomes one complete cross-day gap on both dates',
    () async {
      final evening = DateTime.utc(2026, 10, 9);
      final morning = DateTime.utc(2026, 10, 10);
      final video = Event(
        'video',
        '视频',
        'life',
        evening.add(const Duration(hours: 22)),
        evening.add(const Duration(hours: 23, minutes: 50)),
      );
      final sleep = Event(
        'sleep',
        '睡觉',
        'rest',
        morning.add(const Duration(minutes: 6)),
        morning.add(const Duration(hours: 8)),
      );
      final head = Event(
        undefinedHeadId(morning),
        '刷手机',
        null,
        morning,
        sleep.start,
        '旧备注',
      );
      await store.replaceEvents({
        video.id: video,
        sleep.id: sleep,
        head.id: head,
      });
      // Startup may show a date unrelated to either neighbor; reconcile all
      // records before the user visits the dates containing this gap.
      await controller.initialize();
      expect(controller.rows, isEmpty);
      expect(
        store.events.values.any(
          (gap) =>
              gap.isUndefined &&
              gap.start == video.end &&
              gap.end == sleep.start,
        ),
        isTrue,
      );
      await controller.setDay(evening);
      final gap = controller.rows.singleWhere(
        (gap) => gap.isUndefined && gap.start == video.end,
      );
      expect(gap.end, sleep.start);
      expect(gap.title, '刷手机');
      expect(gap.notes, '旧备注');
      expect(store.events.containsKey(head.id), isFalse);
      await controller.setDay(morning);
      expect(controller.rows.where((event) => event.isUndefined), [gap]);
      await controller.editCell(gap.id, EventColumn.title, '睡前空闲');
      controller.dispose();
      store = await Store.open(directory);
      controller = JournalController(store, day: evening);
      await controller.initialize();
      expect(controller.event(gap.id)!.title, '睡前空闲');
      expect(controller.rows.any((row) => row.id == gap.id), isTrue);
      await controller.setDay(morning);
      final promoted = await controller.editCell(
        gap.id,
        EventColumn.tag,
        'life',
      );
      expect(store.events[promoted]!.start, video.end);
      expect(store.events[promoted]!.end, sleep.start);
      expect(controller.event(gap.id), isNull);
      await controller.undo();
      expect(controller.event(gap.id)!.title, '睡前空闲');
      await controller.redo();
      expect(controller.event(gap.id), isNull);
    },
  );

  test(
    'cross-day boundaries and undo update every day in one atomic write',
    () async {
      final morning = day.add(const Duration(days: 1));
      final video = item('video', 22, 23);
      final sleep = Event(
        'sleep',
        '睡觉',
        'rest',
        morning.add(const Duration(minutes: 6)),
        morning.add(const Duration(hours: 8)),
      );
      await store.replaceEvents({video.id: video, sleep.id: sleep});
      await controller.initialize();
      final gap = controller.rows.singleWhere(
        (gap) => gap.isUndefined && gap.start == video.end,
      );
      await controller.editCell(gap.id, EventColumn.title, '跨天空档');
      final before = await store.eventsFile.readAsBytes();
      final beforeWrites = writes;
      final shifted = video.copyWith(
        end: day.add(const Duration(hours: 23, minutes: 50)),
      );
      failWrites = true;
      await expectLater(
        controller.updateEvent(shifted),
        throwsFileSystemException,
      );
      expect(controller.event(gap.id)!.start, video.end);
      expect(await store.eventsFile.readAsBytes(), before);
      failWrites = false;
      await controller.updateEvent(shifted);
      expect(writes - beforeWrites, 1);
      await controller.setDay(morning);
      expect(controller.event(gap.id)!.start, shifted.end);
      expect(controller.event(gap.id)!.title, '跨天空档');
      await controller.undo();
      expect(controller.event(gap.id)!.start, video.end);
      await controller.redo();
      expect(controller.event(gap.id)!.start, shifted.end);
      controller.select(sleep.id);
      await controller.deleteSelected();
      expect(controller.event(gap.id), isNull);
      expect(controller.rows, isEmpty);
      await controller.undo();
      expect(controller.event(gap.id)!.title, '跨天空档');
    },
  );
}
